#!/usr/bin/env python3
"""clang-format wrapper that understands Logos. Plain sources go straight
through clang-format; .x files first get their %-directives swapped for
parseable ObjC placeholders and restored afterwards, so hook bodies format
like normal methods.

Usage: format.py [--check] [files...]   (defaults to everything under src/)
"""

import argparse
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STYLE = f"file:{ROOT / '.clang-format'}"

PROTECT = [
    (r"^([ \t]*)%hook[ \t]+(.*)$", r"\1@implementation LOGOSHOOK_\2"),
    (r"^([ \t]*)%subclass[ \t]+(.*)$", r"\1@implementation LOGOSSUBCLASS_\2"),
    (r"^([ \t]*)%end[ \t]*$", r"\1@end //LOGOSEND"),
    (r"^([ \t]*)%group[ \t]+(.*)$", r"\1//LOGOSGROUP \2"),
    (r"^([ \t]*)%new[ \t]+([+-])", r"\1/*LOGOSNEW*/\n\1\2"),
    (r"^([ \t]*)%new[ \t]*$", r"\1/*LOGOSNEW*/"),
    (r"^([ \t]*)%property\b(.*)$", r"\1@property\2 //LOGOSPROP"),
    (r"^([ \t]*)%ctor\b", r"\1static void LOGOSCTOR(void)"),
    (r"^([ \t]*)%dtor\b", r"\1static void LOGOSDTOR(void)"),
    (r"%orig\b", "LOGOSORIG"),
    (r"%c\(", "LOGOSC("),
    (r"%init\b", "LOGOSINIT"),
]

RESTORE = [
    (r"@implementation LOGOSHOOK_", "%hook "),
    (r"@implementation LOGOSSUBCLASS_", "%subclass "),
    (r"@end[ \t]*//[ \t]*LOGOSEND", "%end"),
    (r"//[ \t]*LOGOSGROUP ", "%group "),
    (r"^([ \t]*)/\*LOGOSNEW\*/[ \t]*$", r"\1%new"),
    (r"@property(.*;)[ \t]*//[ \t]*LOGOSPROP", r"%property\1"),
    (r"static void LOGOSCTOR\(void\)", "%ctor"),
    (r"static void LOGOSDTOR\(void\)", "%dtor"),
    (r"LOGOSORIG", "%orig"),
    (r"LOGOSC\(", "%c("),
    (r"LOGOSINIT", "%init"),
    (r"[ \t]+$", ""),
]

LEFTOVER = re.compile(r"LOGOS(HOOK_|SUBCLASS_|END|GROUP|NEW|PROP|CTOR|DTOR|ORIG|C\(|INIT)")


def _apply(rules, text):
    for pattern, replacement in rules:
        text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
    return text


def _clang_format(text, assume_filename):
    result = subprocess.run(
        ["clang-format", f"--style={STYLE}", f"--assume-filename={assume_filename}"],
        input=text, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "clang-format failed")
    return result.stdout


def format_file(path):
    """Return the formatted content of path, or raise on formatter failure."""
    original = path.read_text()
    if path.suffix in (".x", ".xm"):
        formatted = _apply(
            RESTORE, _clang_format(_apply(PROTECT, original), path.with_suffix(".m"))
        )
        if LEFTOVER.search(formatted):
            raise RuntimeError(f"leftover Logos placeholder after formatting {path}")
    else:
        formatted = _clang_format(original, path)
    return original, formatted


def main():
    parser = argparse.ArgumentParser(
        description="Format the sources, including Logos .x files."
    )
    parser.add_argument("--check", action="store_true",
                        help="report files that would change without rewriting them")
    parser.add_argument("files", nargs="*", type=Path,
                        help="files to format (defaults to everything under src/)")
    args = parser.parse_args()

    files = args.files or sorted(
        p for p in (ROOT / "src").rglob("*") if p.suffix in (".m", ".h", ".x")
    )

    try:
        with ThreadPoolExecutor() as pool:
            results = list(pool.map(format_file, files))
    except (RuntimeError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    dirty = False
    for path, (original, formatted) in zip(files, results):
        if original == formatted:
            continue
        dirty = True
        if args.check:
            print(f"would reformat: {path}")
        else:
            path.write_text(formatted)
            print(f"reformatted: {path}")

    return 1 if args.check and dirty else 0


if __name__ == "__main__":
    sys.exit(main())
