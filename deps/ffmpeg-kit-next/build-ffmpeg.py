#!/usr/bin/env python3
"""Builds the ffmpeg stack in build/ from source:
FFmpeg + the ffmpeg-kit-next Objective-C wrapper (libffmpegkit),
compiled for iOS arm64 against the Theos SDK, with the Theos toolchain on
Linux or Xcode's clang on macOS (which is what Theos itself uses there).
TLS comes from the system SecureTransport backend, so no OpenSSL is needed.

FFMPEG_TAG must match what the upstream submodule checkout expects
(scripts/source.sh in the submodule).
"""

import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

MIN_IOS = "14.0"

FFMPEG_TAG = "n8.1.2"

KIT_DIR = Path(__file__).resolve().parent
KIT_SRC = KIT_DIR / "upstream/apple/src"
OUT_DIR = KIT_DIR / "build"
BUILD = Path(os.environ.get("BUILD_DIR", "/tmp/nfb-ffmpeg-build"))

CONFIGURE_FLAGS = [
    "--enable-cross-compile",
    "--target-os=darwin",
    "--arch=aarch64",
    "--cpu=armv8",
    "--extra-cflags=-Wno-unused-function -Wno-deprecated-declarations -fstrict-aliasing",
    "--disable-shared",
    "--enable-static",
    "--enable-pthreads",
    "--enable-small",
    "--disable-programs",
    "--disable-doc",
    "--disable-debug",
    "--disable-zlib",
    "--disable-bzlib",
    "--disable-iconv",
    "--disable-audiotoolbox",
    "--disable-avfoundation",
    "--disable-coreimage",
    "--enable-securetransport",
    "--enable-videotoolbox",
    "--disable-everything",
    "--enable-protocol=file,tcp,tls,http,https,crypto,data",
    "--enable-demuxer=hls,mpegts,mov,aac",
    "--enable-decoder=h264,hevc,aac",
    "--enable-parser=h264,hevc,aac",
    "--enable-encoder=h264_videotoolbox,gif",
    "--enable-muxer=mp4,gif",
    "--enable-filter=scale,format,null,anull,split,palettegen,paletteuse",
    "--enable-bsf=aac_adtstoasc,extract_extradata",
]


def run(args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def capture(args):
    return subprocess.run(
        args, check=True, stdout=subprocess.PIPE, text=True
    ).stdout.strip()


def toolchain():
    """SDK from $THEOS/sdks on every platform; compilers from the Theos Linux
    toolchain when present, else Xcode via xcrun."""
    if not os.environ.get("THEOS"):
        sys.exit("THEOS is not set; export it to your Theos install.")
    theos = Path(os.environ["THEOS"])
    sdk = os.environ.get("SDK")
    if not sdk:
        sdks = sorted(
            theos.glob("sdks/iPhoneOS*.sdk"),
            key=lambda p: [int(n) for n in re.findall(r"\d+", p.name)],
        )
        sdk = str(sdks[-1]) if sdks else ""

    bin_dir = theos / "toolchain/linux/iphone/bin"
    if (bin_dir / "clang").is_file():
        tools = {
            name: str(bin_dir / name)
            for name in ("clang", "clang++", "ar", "ranlib", "nm")
        }
    else:
        tools = {
            name: capture(["xcrun", "-f", name])
            for name in ("clang", "clang++", "ar", "ranlib", "nm")
        }
    return {
        "sdk": sdk,
        "cc": tools["clang"],
        "cxx": tools["clang++"],
        "ar": tools["ar"],
        "ranlib": tools["ranlib"],
        "nm": tools["nm"],
    }


def write_wrappers(tools):
    """Wrapper compilers so build systems that mangle multi-word CC still work."""
    for name, compiler in (("ios-clang", tools["cc"]), ("ios-clang++", tools["cxx"])):
        wrapper = BUILD / "bin" / name
        wrapper.write_text(
            "#!/usr/bin/env bash\n"
            f'exec "{compiler}" -target arm64-apple-ios{MIN_IOS} -isysroot "{tools["sdk"]}" '
            f'-miphoneos-version-min={MIN_IOS} "$@"\n'
        )
        wrapper.chmod(0o755)
    os.environ["PATH"] = f"{BUILD / 'bin'}:{os.environ['PATH']}"


def fetch(url, out):
    if not out.is_file():
        run(["curl", "-fL", "--retry", "3", "-o", str(out), url])


def build_ffmpeg(tools, jobs):
    src = BUILD / f"FFmpeg-{FFMPEG_TAG}"
    prefix = BUILD / "ffmpeg-install"
    if (prefix / "lib/libavcodec.a").is_file():
        return src, prefix

    fetch(
        f"https://github.com/arthenica/FFmpeg/archive/refs/tags/{FFMPEG_TAG}.tar.gz",
        BUILD / "ffmpeg.tar.gz",
    )
    shutil.rmtree(src, ignore_errors=True)
    run(["tar", "-xzf", str(BUILD / "ffmpeg.tar.gz"), "-C", str(BUILD)])

    # Trimmed to what the media download flows use: probe and demux Twitter
    # HLS/MP4 over HTTPS, decode H.264/HEVC/AAC, scale, encode with the
    # VideoToolbox hardware H.264 encoder or the palette-based GIF pipeline,
    # mux to mp4/gif. Component selection pulls transitive deps (e.g. hls
    # demuxer brings mov/mpegts/aac).
    run(
        [
            "./configure",
            f"--prefix={prefix}",
            "--cc=ios-clang",
            "--cxx=ios-clang++",
            "--as=ios-clang",
            f"--ar={tools['ar']}",
            f"--ranlib={tools['ranlib']}",
            f"--nm={tools['nm']}",
            *CONFIGURE_FLAGS,
        ],
        cwd=src,
    )
    run(["make", f"-j{jobs}"], cwd=src)
    run(["make", "install"], cwd=src)
    # Keep the tree for config.h (the kit build needs it), drop the objects.
    run(["make", "clean"], cwd=src)
    return src, prefix


def build_kit(tools, ffmpeg_src, ffmpeg_prefix, jobs):
    kit_build = BUILD / "ffmpegkit-obj"
    shutil.rmtree(kit_build, ignore_errors=True)
    kit_build.mkdir(parents=True)

    cflags = [
        f"-I{KIT_SRC}",
        f"-I{ffmpeg_src}",
        f"-I{ffmpeg_prefix / 'include'}",
        "-DFFMPEG_KIT_ARM64",
        "-DIOS",
        f"-DFFMPEG_KIT_BUILD_DATE={date.today().strftime('%Y%m%d')}",
        "-Oz",
        "-fstrict-aliasing",
        "-Wno-unused-function",
        "-Wno-deprecated-declarations",
    ]

    # Source list from apple/src/Makefile.am.
    am = (KIT_SRC / "Makefile.am").read_text()
    section = re.search(
        r"^libffmpegkit_la_SOURCES.*?(?=^\s*$)", am, re.MULTILINE | re.DOTALL
    )
    sources = re.findall(r"[A-Za-z0-9_/]+\.[mc]\b", section.group(0))

    def compile_source(src):
        obj = kit_build / (src.replace("/", "_") + ".o")
        arc = ["-fobjc-arc"] if src.endswith(".m") else []
        run(["ios-clang", *arc, *cflags, "-c", str(KIT_SRC / src), "-o", str(obj)])
        return obj

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        objects = list(pool.map(compile_source, sources))

    archive = kit_build / "libffmpegkit.a"
    run([tools["ar"], "rcs", str(archive), *map(str, objects)])
    run([tools["ranlib"], str(archive)])
    return archive


def install(ffmpeg_prefix, kit_archive):
    shutil.rmtree(OUT_DIR, ignore_errors=True)
    (OUT_DIR / "lib/pkgconfig").mkdir(parents=True)
    for header in KIT_SRC.glob("*.h"):
        shutil.copy(header, OUT_DIR)
    shutil.copytree(ffmpeg_prefix / "include", OUT_DIR, dirs_exist_ok=True)
    for lib in [*ffmpeg_prefix.glob("lib/*.a"), kit_archive]:
        shutil.copy(lib, OUT_DIR / "lib")
    for pc in ffmpeg_prefix.glob("lib/pkgconfig/*.pc"):
        shutil.copy(pc, OUT_DIR / "lib/pkgconfig")


def main():
    tools = toolchain()
    if not Path(tools["sdk"]).is_dir():
        print("iPhoneOS SDK not found", file=sys.stderr)
        return 1
    if not (KIT_SRC / "FFmpegKit.m").is_file():
        print(
            "ffmpeg-kit-next submodule missing; run: "
            "git submodule update --init deps/ffmpeg-kit-next/upstream",
            file=sys.stderr,
        )
        return 1

    (BUILD / "bin").mkdir(parents=True, exist_ok=True)
    write_wrappers(tools)

    jobs = os.cpu_count() or 4
    ffmpeg_src, ffmpeg_prefix = build_ffmpeg(tools, jobs)
    kit_archive = build_kit(tools, ffmpeg_src, ffmpeg_prefix, jobs)
    install(ffmpeg_prefix, kit_archive)

    print(f"Done. Headers and libraries installed in {OUT_DIR}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
