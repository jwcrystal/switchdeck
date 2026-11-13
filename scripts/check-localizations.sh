#!/bin/bash
# Verifies the localisation files against the source.
#
# Keys are the English literals passed to t()/tf(), so a missing entry shows up
# as English at runtime rather than as an error. This script is the guard:
#   - every t()/tf() key must exist in every Resources/<lang>.lproj file
#   - a translation must keep the same %@ / %d / %% placeholders
#   - entries no source mentions are reported, so dead keys do not pile up
#
# Run: ./scripts/check-localizations.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, re, sys

sources = "\n".join(p.read_text() for p in pathlib.Path("Sources").rglob("*.swift"))

# t("...") and tf("..."), including the multi-line calls the code uses.
def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")

keys = set()
for m in re.finditer(r'\b(?:t|tf)\(\s*"((?:[^"\\]|\\.)*)"', sources):
    keys.add(unescape(m.group(1)))

def parse(path):
    text = path.read_text()
    entries = {}
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text):
        entries[unescape(m.group(1))] = unescape(m.group(2))
    return entries

def placeholders(s):
    return sorted(re.findall(r'%[@d%]', s))

failed = False
files = sorted(pathlib.Path("Resources").glob("*.lproj/Localizable.strings"))
if not files:
    print("no Resources/<lang>.lproj/Localizable.strings found")
    sys.exit(1)

for path in files:
    entries = parse(path)
    missing = sorted(k for k in keys if k not in entries)
    bad = sorted(
        (k, v) for k, v in entries.items()
        if placeholders(k) != placeholders(v)
    )
    unused = sorted(k for k in entries if k not in keys)
    print(f"{path}: {len(entries)} entries, {len(missing)} missing, {len(bad)} placeholder mismatches")
    for k in missing:
        print(f"  missing: {k!r}")
    for k, v in bad:
        print(f"  placeholders differ: {k!r} -> {v!r}")
    if unused:
        print(f"  note: {len(unused)} keys no t() call mentions (SwiftUI literals are expected here)")
        for k in unused[:5]:
            print(f"    {k!r}")
    failed = failed or bool(missing or bad)

# Unwrapped AppKit text is invisible to every other check: the key exists, the
# translation is correct, and the view still shows English because the literal
# never went through t(). This is how the menu extras shipped untranslated.
unwrapped = []
appkit = re.compile(
    r'(?:NSMenuItem\(title:|addButton\(withTitle:|labelWithString:|NSButton\(title:|messageText\s*=)\s*"[^"]'
)
for path in sorted(pathlib.Path("Sources").rglob("*.swift")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if appkit.search(line) and "t(" not in line:
            unwrapped.append(f"{path.name}:{number} {line.strip()[:80]}")

if unwrapped:
    print(f"\n{len(unwrapped)} user-facing AppKit strings never reach t():")
    for item in unwrapped:
        print(f"  {item}")
    failed = True

sys.exit(1 if failed else 0)
PY
