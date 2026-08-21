#!/usr/bin/env python3
"""Theos tweak builder with required flags.

IPA builds are assembled by patina: the tweak output as an overlay, the runtime
tweak packages it depends on, and a config bundle holding the branding assets.
"""

import argparse
import concurrent.futures
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CACHE_DIR = ROOT / ".cache"
THEOS_DIR = ROOT / ".theos"

# The only file to edit: the deb control and the Substrate filter plist are
# generated from it, and the Makefile takes its settings from it through the
# environment. Every key but these becomes a control field.
TWEAK_JSON = ROOT / "tweak.json"
BUILD_FIELDS = {"filter", "build"}

# Resources, installed as <name>/<name>.bundle under Application Support. The
# strings file and its schema are the exception: they are the source the .lproj
# tables are built from, so they are staged rather than shipped as they stand.
BUNDLE_DIR = ROOT / "bundle"
STRINGS = BUNDLE_DIR / "strings.json"
STRINGS_SCHEMA = BUNDLE_DIR / "strings.schema.json"

# The nested bundle the tables are built into, so the .lproj directories don't
# crowd the bundle root. A bundle rather than a plain directory because that is
# what NSBundle's localized lookups reach into; the tweak finds it by the same
# name, through TWEAK_STRINGS_BUNDLE_STRING.
STRINGS_BUNDLE = "Localizations"

# Cocoa's default table, and so the tweak's own interface strings: it sets the
# languages shipped, and a key it hasn't been translated into falls back to
# SOURCE_LANGUAGE, since English in the UI beats a raw key. Every other table is
# strictly per-language, having been written for the language it replaces text
# in, and is only built for the languages it has values for.
PRIMARY_TABLE = "Localizable"
SOURCE_LANGUAGE = "en"

STRINGS_ESCAPES = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t"}

# The branding, as a patina config bundle; a zip of the same layout works too.
REBRAND_DIR = ROOT / "patina"

# Home-screen shortcut icons restored when rebranding, taken from the tweak
# bundle's classic SVGs rather than committed to the config bundle as copies.
SHORTCUT_ICONS = {
    "icn_applicationshortcut_tweet": "compose.svg",
    "icn_applicationshortcut_DM": "compose_dm.svg",
    "icn_applicationshortcut_grok": "grok_blackhole_icon.svg",
}

# A decrypted IPA of the target app, which patina edits the tweak into.
BASE_IPA = ROOT / "packages/base.ipa"

# Theos has no rootful scheme of its own: to it, rootful is the absence of one,
# and naming it would be an error.
SCHEMES = {
    "rootful": {"architecture": "iphoneos-arm", "theos": ""},
    "rootless": {"architecture": "iphoneos-arm64", "theos": "rootless"},
}

IPA_MODES = ("sideloaded", "trollstore")

# Without a filter plist Theos can't stage these, so they ride into an IPA as
# an overlay rather than coming from the deb like the rest.
SIDELOAD_ONLY_DYLIBS = {"zxPluginsInject.dylib"}

# The release is tagged with a leading v, the assets in it are not.
PATINA_VERSION = "0.4.0"
PATINA_URL = "https://github.com/theacrat/patina/releases/download/v{v}/patina-{v}-{triple}.tar.gz"


class BuildError(Exception):
    """Raised for a failed build step; maps to a fatal non-zero exit."""


def say(message):
    if sys.stdout.isatty():
        print(f"\033[1;32m{message}\033[0m", flush=True)
    else:
        print(message, flush=True)


def run(args):
    subprocess.run(args, cwd=ROOT, check=True)


def setting(build, key):
    """A build setting from tweak.json, overridable from the environment so CI
    can change one without editing the file."""
    value = os.environ.get(f"TWEAK_{key.upper()}")
    if value is None:
        value = build.get(key, "")
    return " ".join(value) if isinstance(value, list) else str(value)


def make_env(scheme, release):
    """The Makefile takes every setting from the environment, so read them out
    of tweak.json here. Theos settles its schema and its paths from the same
    place, which keeps each scheme's build in a tree of its own."""
    info = json.loads(TWEAK_JSON.read_text())
    build = info.get("build", {})
    commit = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()

    # Include paths are written relative to the repo, not to the scratch dir.
    cflags = [
        f"-I{ROOT / flag[2:]}" if flag.startswith("-I") else flag
        for flag in build.get("cflags", [])
    ] + [
        f"""-DTWEAK_NAME_STRING='"{info["name"]}"'""",
        f"""-DTWEAK_STRINGS_BUNDLE_STRING='"{STRINGS_BUNDLE}"'""",
        f"""-DTWEAK_VERSION_STRING='"{info["version"]}"'""",
        f"""-DTWEAK_COMMIT_STRING='"{commit or "unknown"}"'""",
    ]

    return {
        **os.environ,
        "THEOS_PACKAGE_SCHEME": SCHEMES[scheme]["theos"],
        "THEOS_BUILD_DIR": str(ROOT),
        # Spelling the version out drops the build number Theos would otherwise
        # count up on every packaging run. Anything but a release is marked with
        # the commit it came from.
        "PACKAGE_VERSION": info["version"]
        + ("" if release else f"+{commit or 'unknown'}"),
        "_THEOS_LOCAL_DATA_DIR": str(THEOS_DIR / scheme),
        # Theos stages the payload from the name and reads the control from the
        # path, so both have to be set.
        "THEOS_LAYOUT_DIR_NAME": str(layout_dir(scheme)),
        "THEOS_LAYOUT_DIR": str(layout_dir(scheme)),
        # A release build is optimised and stripped; Theos names the object
        # directory after whichever of the two it is, which obj_dir matches.
        "FINALPACKAGE" if release else "DEBUG": "1",
        "ARCHS": setting(build, "archs"),
        "TARGET": f"iphone:clang:{setting(build, 'sdk_version')}"
        f":{setting(build, 'target_version')}",
        "TWEAK_NAME": info["name"],
        "TWEAK_FILES": " ".join(source_files()),
        "TWEAK_FRAMEWORKS": setting(build, "frameworks"),
        "TWEAK_PRIVATE_FRAMEWORKS": setting(build, "private_frameworks"),
        "TWEAK_EXTRA_FRAMEWORKS": setting(build, "extra_frameworks"),
        "TWEAK_OBJ_FILES": " ".join(
            str(path)
            for pattern in build.get("obj_files", [])
            for path in sorted(ROOT.glob(pattern))
        ),
        "TWEAK_CFLAGS": " ".join(cflags),
        "TWEAK_SUBPROJECTS": " ".join(
            str(ROOT / "deps" / project) for project in build.get("subprojects", [])
        ),
    }


def source_files():
    return sorted(
        str(path) for suffix in ("x", "m") for path in ROOT.glob(f"src/**/*.{suffix}")
    )


def write_filter(workdir):
    """Theos reads the Substrate filter from a plist beside the Makefile."""
    info = json.loads(TWEAK_JSON.read_text())
    (workdir / f"{info['name']}.plist").write_bytes(
        plistlib.dumps({"Filter": {"Bundles": info["filter"]["bundles"]}})
    )


def obj_dir(scheme="rootful", release=False):
    return THEOS_DIR / scheme / ("obj" if release else "obj/debug")


def layout_dir(scheme):
    return CACHE_DIR / f"layout-{scheme}"


def make(scheme, *args, release=False):
    """Theos builds from the directory it is run in, and writes the filter plist
    it finds there into the package, so give each scheme one of its own with the
    repo's Makefile linked in."""
    workdir = CACHE_DIR / f"make-{scheme}"
    workdir.mkdir(parents=True, exist_ok=True)
    link = workdir / "Makefile"
    if not link.is_symlink():
        link.symlink_to(ROOT / "Makefile")
    write_filter(workdir)
    subprocess.run(
        ["make", *args],
        cwd=workdir,
        check=True,
        env=make_env(scheme, release),
    )


def make_sideload_projects(scheme, release):
    """The sideload-only projects can't be staged, so they are built from their
    own directories rather than through the aggregate: the deb stays clean and
    the main tweak isn't compiled a second time. The shared data dir still
    lands their output in this scheme's tree."""
    build = json.loads(TWEAK_JSON.read_text()).get("build", {})
    for project in build.get("sideload_subprojects", []):
        subprocess.run(
            ["make"],
            cwd=ROOT / "deps" / project,
            check=True,
            env=make_env(scheme, release),
        )


def tweak_info(field):
    info = json.loads(TWEAK_JSON.read_text())
    if field not in info:
        raise BuildError(f"no {field} in {TWEAK_JSON.name}")
    return info[field]


def patina_triple():
    machine = os.uname().machine.lower()
    if sys.platform == "darwin":
        return "aarch64-apple-darwin" if machine == "arm64" else "x86_64-apple-darwin"
    if sys.platform.startswith("linux"):
        if machine in ("x86_64", "amd64"):
            return "x86_64-unknown-linux-musl"
        if machine in ("aarch64", "arm64"):
            return "aarch64-unknown-linux-musl"
    return None


def patina_binary():
    """Locate the patina binary: $PATINA, then PATH, then the pinned release
    build for this platform. PATINA may point at the binary or at a local
    checkout, which is built on demand."""
    env = os.environ.get("PATINA")
    if env:
        path = Path(env)
        if path.is_dir():
            say("Building patina from local checkout.")
            subprocess.run(["cargo", "build", "--release"], cwd=path, check=True)
            return path / "target/release/patina"
        if path.is_file():
            return path
        raise BuildError(f"PATINA does not exist: {env}")
    found = shutil.which("patina")
    if found:
        return Path(found)

    binary = CACHE_DIR / f"patina-{PATINA_VERSION}"
    if not binary.is_file():
        triple = patina_triple()
        if not triple:
            raise BuildError(
                "no patina release build for this platform; install patina "
                "(https://github.com/theacrat/patina) or set PATINA"
            )
        url = PATINA_URL.format(v=PATINA_VERSION, triple=triple)
        tgz = fetch(url, f"patina-{PATINA_VERSION}-{triple}.tar.gz")
        with tarfile.open(tgz) as tf:
            binary.write_bytes(tf.extractfile("patina").read())
        binary.chmod(0o755)
        if sys.platform == "darwin":
            # Only a downloader that opts into quarantine sets this, so it
            # should be absent here; clearing it needs no permission anyway.
            subprocess.run(
                ["xattr", "-d", "com.apple.quarantine", str(binary)],
                stderr=subprocess.DEVNULL,
            )
    return binary


def fetch(url, name):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    dest = CACHE_DIR / name
    if not dest.exists():
        say(f"Fetching {name}.")
        try:
            urllib.request.urlretrieve(url, dest)
        except OSError as exc:
            dest.unlink(missing_ok=True)
            raise BuildError(f"failed to fetch {name}: {exc}")
    return dest


def runtime_deps():
    """The packages behind the control file's Depends. A jailbreak installs
    them itself; an IPA has to carry them, so anything with somewhere to get it
    from is fetched or taken from the tree. A path wins over a url, which is
    how a locally built package is tested in place of the published one."""
    debs = []
    for dep in tweak_info("depends"):
        if not isinstance(dep, dict):
            continue
        if "path" in dep:
            path = ROOT / dep["path"]
            if not path.is_file():
                raise BuildError(f"{dep['name']}: no package at {dep['path']}")
            debs.append(path)
        elif "url" in dep:
            debs.append(fetch(dep["url"], dep["url"].rsplit("/", 1)[-1]))
    return debs


def deb_path(scheme):
    """Where a built deb ends up, named like the IPAs. Theos names its output
    after the package with a revision that climbs on every build, so it is
    renamed to this and the last one is replaced rather than piling up."""
    return (
        ROOT / "packages" / f"{tweak_info('name')}-{scheme}_{tweak_info('version')}.deb"
    )


def collect_deb(scheme):
    """Take what Theos just packaged and put it where the rest of the build
    expects to find it."""
    package = tweak_info("package")
    arch = SCHEMES[scheme]["architecture"]
    built = sorted(
        (ROOT / "packages").glob(f"{package}_*_{arch}.deb"),
        key=lambda path: path.stat().st_mtime,
    )
    if not built:
        raise BuildError(f"Theos packaged no {arch} deb.")
    target = deb_path(scheme)
    target.unlink(missing_ok=True)
    built[-1].replace(target)
    return target


def report(package):
    """What the build produced, for a workflow step to pick up."""
    if not os.environ.get("GITHUB_OUTPUT"):
        return
    with open(os.environ["GITHUB_OUTPUT"], "a") as f:
        f.write(f"package={package}\n")
        f.write(f"name={tweak_info('name')}\n")
        f.write(f"version={tweak_info('version')}\n")


def sideload_dylibs(mode, release):
    if mode != "sideloaded":
        return []
    dylibs = []
    for name in sorted(SIDELOAD_ONLY_DYLIBS):
        path = obj_dir(release=release) / name
        if not path.is_file():
            raise BuildError(f"{name} not found. Build first or drop --package-only.")
        dylibs.append(path)
    return dylibs


def control_value(value):
    """A dependency is written by name, whatever else it records about where to
    get it from."""
    if isinstance(value, list):
        return ", ".join(
            item["name"] if isinstance(item, dict) else str(item) for item in value
        )
    return str(value)


def read_strings():
    """{table: {key: {language: value}}} from the strings file, with the
    languages the tweak ships. Language codes are checked against the schema's
    own list, so the two can't drift apart."""
    if not STRINGS_SCHEMA.is_file():
        raise BuildError(f"{STRINGS.name} has no {STRINGS_SCHEMA.name} beside it.")

    document = json.loads(STRINGS.read_text(encoding="utf-8"))
    schema = json.loads(STRINGS_SCHEMA.read_text(encoding="utf-8"))
    known = set(schema["$defs"]["translations"]["properties"])

    tables = {name: table for name, table in document.items() if name != "$schema"}
    if PRIMARY_TABLE not in tables:
        raise BuildError(f"No {PRIMARY_TABLE} table to take the languages from.")

    for name, table in tables.items():
        for key, values in table.items():
            for language, value in values.items():
                where = f"{name}.{key}.{language}"
                if language not in known:
                    raise BuildError(f"{where}: not a language code the schema allows.")
                if not isinstance(value, str) or not value.strip():
                    raise BuildError(f"{where}: not a string.")

    shipped = table_languages(tables[PRIMARY_TABLE])
    for name, table in tables.items():
        unknown = table_languages(table) - shipped
        if unknown:
            raise BuildError(
                f"{name}: languages the tweak doesn't ship: {sorted(unknown)}."
            )

    return tables, shipped


def table_languages(table):
    return {language for values in table.values() for language in values}


def strings_escape(text):
    return "".join(STRINGS_ESCAPES.get(character, character) for character in text)


def strings_table(table, language, fallback=None):
    lines = ["/* Generated from localisation/strings.json — do not edit. */", ""]
    for key, values in table.items():
        value = values.get(language, values.get(fallback))
        if value is not None:
            lines.append(f'"{strings_escape(key)}" = "{strings_escape(value)}";')

    return "\n".join(lines) + "\n"


def stage_strings(bundle):
    """Write each table into a nested bundle of .lproj directories, and name the
    keys still waiting on a translation rather than letting them pass quietly. A
    tweak with no strings file has nothing to build."""
    if not STRINGS.is_file():
        return

    tables, shipped = read_strings()
    localizations = bundle / f"{STRINGS_BUNDLE}.bundle"
    for name, table in tables.items():
        primary = name == PRIMARY_TABLE
        for language in sorted(shipped if primary else table_languages(table)):
            directory = localizations / f"{language}.lproj"
            directory.mkdir(parents=True, exist_ok=True)
            (directory / f"{name}.strings").write_text(
                strings_table(table, language, SOURCE_LANGUAGE if primary else None),
                encoding="utf-8",
            )

    # A resource bundle of its own, so NSBundle treats it as one and resolves
    # the language against its .lproj directories.
    (localizations / "Info.plist").write_bytes(
        plistlib.dumps(
            {
                "CFBundleIdentifier": f"{tweak_info('package')}.{STRINGS_BUNDLE.lower()}",
                "CFBundleDevelopmentRegion": SOURCE_LANGUAGE,
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundlePackageType": "BNDL",
            }
        )
    )

    for key, values in tables[PRIMARY_TABLE].items():
        missing = sorted(shipped - set(values))
        if missing:
            say(f"{key} is untranslated in {', '.join(missing)}; using English.")


def stage_theos(scheme):
    """Write what Theos reads where it looks for it: the tweak's resources and
    the deb control, both in the layout dir Theos is pointed at."""
    info = json.loads(TWEAK_JSON.read_text())
    name = info["name"]

    layout = layout_dir(scheme)
    shutil.rmtree(layout, ignore_errors=True)
    bundle = layout / f"Library/Application Support/{name}/{name}.bundle"
    shutil.copytree(
        BUNDLE_DIR,
        bundle,
        copy_function=os.link,
        ignore=shutil.ignore_patterns(STRINGS.name, STRINGS_SCHEMA.name),
    )
    stage_strings(bundle)

    fields = {
        field: value for field, value in info.items() if field not in BUILD_FIELDS
    }
    fields["architecture"] = SCHEMES[scheme]["architecture"]
    control = "".join(
        f"{field.title()}: {control_value(value)}\n" for field, value in fields.items()
    )
    (layout / "DEBIAN").mkdir(parents=True)
    (layout / "DEBIAN/control").write_text(control)


def bundle_config(bundle):
    if not bundle:
        return {}
    path = Path(bundle)
    try:
        if path.is_dir():
            data = (path / "config.json").read_bytes()
        else:
            with zipfile.ZipFile(path) as z:
                data = z.read("config.json")
        return json.loads(data)
    except (OSError, KeyError, ValueError, zipfile.BadZipFile):
        return {}


def build_config(rebrand, mode, workdir, release):
    """Everything the build needs in one config bundle: the tweak packages, the
    sideload-only dylibs, and the branding — the last only when rebranding, so
    an unbranded build still takes the settings but keeps the app's own name and
    artwork."""
    source = Path(rebrand or REBRAND_DIR)
    settings = bundle_config(source)
    config = workdir / "patina"
    if not rebrand:
        config.mkdir()
        settings.pop("name", None)
    elif source.is_dir():
        shutil.copytree(source, config)
    else:
        config.mkdir()
        with zipfile.ZipFile(source) as bundle:
            bundle.extractall(config)

    if rebrand:
        car = config / "car"
        car.mkdir(exist_ok=True)
        for asset, svg in SHORTCUT_ICONS.items():
            icon = BUNDLE_DIR / "svgs" / svg
            target = car / f"{asset}.svg"

            if icon.is_file() and not target.exists():
                target.symlink_to(icon)

    tweaks = config / "tweaks"
    tweaks.mkdir(exist_ok=True)
    tweak_deb = deb_path("rootful")
    if not tweak_deb.is_file():
        raise BuildError(
            f"{tweak_deb.relative_to(ROOT)} not found. "
            "Build first or drop --package-only."
        )
    for deb in [tweak_deb, *runtime_deps()]:
        shutil.copyfile(deb, tweaks / deb.name)

    for dylib in sideload_dylibs(mode, release):
        frameworks = config / "overlay/Frameworks"
        frameworks.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(dylib, frameworks / dylib.name)

    (config / "config.json").write_text(json.dumps(settings))
    return config


def app_info(ipa):
    with zipfile.ZipFile(ipa) as z:
        plist = next(
            n
            for n in z.namelist()
            if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)
        )
        return plistlib.loads(z.read(plist))


def ensure_ffmpeg():
    """The ffmpeg stack is built from source, not tracked."""
    if (ROOT / "deps/ffmpeg-kit-next/build/lib/libffmpegkit.a").is_file():
        return
    say("ffmpeg libraries not found; building them from source (this takes a while).")
    run(["git", "submodule", "update", "--init", "deps/ffmpeg-kit-next/upstream"])
    run([sys.executable, str(ROOT / "deps/ffmpeg-kit-next/build-ffmpeg.py")])


def prepare_tree(clean):
    """Each scheme has its own tree, so only an explicit clean wipes one."""
    if clean:
        shutil.rmtree(CACHE_DIR, ignore_errors=True)
        shutil.rmtree(THEOS_DIR, ignore_errors=True)


def package_ipa(mode, rebrand, release):
    if not BASE_IPA.exists():
        raise BuildError(f"{BASE_IPA.relative_to(ROOT)} not found.")

    name = tweak_info("name")
    version = tweak_info("version")
    info = app_info(BASE_IPA)
    app_name = bundle_config(rebrand).get("name") or info.get(
        "CFBundleDisplayName", "app"
    )
    token = "".join(c for c in app_name if c.isalnum())
    ext = "tipa" if mode == "trollstore" else "ipa"
    output = (
        f"{name}-{mode}-{token}_{version}_{info['CFBundleShortVersionString']}.{ext}"
    )

    say(f"Building the IPA: {output}.")
    out_path = ROOT / "packages" / output
    out_path.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory(prefix=f"{name}-") as workdir:
        config = build_config(rebrand, mode, Path(workdir), release)
        run(
            [
                str(patina_binary()),
                "edit",
                str(BASE_IPA),
                "-o",
                str(out_path),
                "--config",
                str(config),
            ]
        )

    say(f"{name} has been successfully built. Enjoy!")
    return output


def build_scheme(scheme, modes, args):
    """One package scheme, start to finish. Schemes have separate trees, so
    this is safe to run for both at once."""
    if not args.package_only:
        stage_theos(scheme)
        make(scheme, "package", release=args.release)
        collect_deb(scheme)
        if "sideloaded" in modes:
            make_sideload_projects(scheme, args.release)

    built = [deb_path(scheme).name for m in modes if m not in IPA_MODES]
    ipas = [m for m in modes if m in IPA_MODES]
    if ipas:
        with concurrent.futures.ThreadPoolExecutor() as pool:
            built += pool.map(
                lambda m: package_ipa(m, args.rebrand, args.release), ipas
            )
    return built


def main():
    name = tweak_info("name")
    parser = argparse.ArgumentParser(
        description=f"Build {name} in one or more deployment formats.",
    )
    for flag, help_text in (
        ("rootful", "a .deb for rootful jailbreaks"),
        ("rootless", "a .deb for rootless jailbreaks"),
        (
            "sideloaded",
            "a .ipa you can sideload with AltStore, Sideloadly or similar",
        ),
        ("trollstore", "a .tipa you can install with TrollStore"),
    ):
        parser.add_argument(
            f"--{flag}",
            dest="modes",
            action="append_const",
            const=flag,
            help=f"build {name} as {help_text}",
        )
    parser.add_argument(
        "--release",
        action="store_true",
        help="build optimised and stripped instead of unoptimised with symbols",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="wipe previous build output first instead of building incrementally",
    )
    parser.add_argument(
        "--package-only",
        action="store_true",
        help="skip compiling and package existing dylibs from .theos (IPA builds only)",
    )
    parser.add_argument(
        "--rebrand",
        nargs="?",
        const=str(REBRAND_DIR),
        metavar="DIR|ZIP",
        help=f"rebrand the app from a patina config bundle: name, icons and "
        f"overlaid files (IPA builds only, defaults to {REBRAND_DIR.name}/)",
    )
    args = parser.parse_args()

    if not args.modes:
        parser.error("choose at least one format to build.")
    # Rebranding an IPA alongside a deb is fine; the deb just ignores it. Only
    # compiling can't be skipped, since a deb is packaged straight from it.
    if args.rebrand and not any(mode in IPA_MODES for mode in args.modes):
        parser.error("--rebrand is only valid with --sideloaded or --trollstore.")
    if args.package_only and any(mode not in IPA_MODES for mode in args.modes):
        parser.error("--package-only is only valid with --sideloaded or --trollstore.")
    if args.rebrand and not Path(args.rebrand).exists():
        parser.error(f"--rebrand bundle not found: {args.rebrand}")

    # Grouped by package scheme: the IPAs are packaged from the rootful build,
    # so they share its tree, while rootless has one of its own.
    groups = {
        "rootless": ["rootless"] if "rootless" in args.modes else [],
        "rootful": [
            m for m in ("rootful", "sideloaded", "trollstore") if m in args.modes
        ],
    }

    try:
        if not args.package_only:
            if not os.environ.get("THEOS"):
                raise BuildError("THEOS is not set; export it to your Theos install.")
            ensure_ffmpeg()

        prepare_tree(args.clean)
        wanted = {s: m for s, m in groups.items() if m}
        for scheme, modes in wanted.items():
            say(f"Preparing to compile {name} for {', '.join(modes)}.")

        with concurrent.futures.ThreadPoolExecutor() as pool:
            built = pool.map(
                lambda item: build_scheme(*item, args), list(wanted.items())
            )
        for package in [p for group in built for p in group]:
            report(package)
    except BuildError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"Error: command failed: {' '.join(map(str, exc.cmd))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
