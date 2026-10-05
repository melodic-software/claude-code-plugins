#!/usr/bin/env bash
# Contract test for build-variants.py. Expected values come from the defect
# catalog (D1-D9, C0, C1 and their injections), not from the builder's output.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../../.." && pwd)"

# shellcheck source=../../../../../scripts/lib/python-probe.sh
. "$ROOT/scripts/lib/python-probe.sh"
PYTHON=""
python_probe::require_to PYTHON "$HERE/build-variants.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

build() {
  "$PYTHON" "$HERE/build-variants.py" --out "$1/variants" --map "$1/variant-map.json" >/dev/null
}

build "$TMP/a"
build "$TMP/b"
build "$TMP/a"
"$PYTHON" "$HERE/build-variants.py" >/dev/null

if grep -rEl 'https?://' "$HERE/site" "$HERE/variants" "$TMP/a"; then
  fail "external URL under site/ or variants/"
fi

mkdir -p "$TMP/neg"
cp -R "$HERE/site" "$TMP/neg/site"
printf '%s\n' '{"base": "site/index.html", "defects": [{"id": "X", "name": "x", "patches": [{"find": "not in the page", "replace": ""}]}]}' >"$TMP/neg/defects.json"
if "$PYTHON" "$HERE/build-variants.py" --defects "$TMP/neg/defects.json" --out "$TMP/neg/variants" --map "$TMP/neg/map.json" 2>"$TMP/neg/err"; then
  fail "builder accepted a patch whose anchor is absent"
fi
grep -q 'matched 0 times' "$TMP/neg/err" || fail "unexpected builder error: $(cat "$TMP/neg/err")"

"$PYTHON" - "$HERE" "$TMP/a" "$TMP/b" <<'PY'
import hashlib
import re
import sys
from pathlib import Path
import json

here, a, b = (Path(p) for p in sys.argv[1:4])
errors = []


def check(ok, message):
    if not ok:
        errors.append(message)


def manifest(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob("*")) if p.is_file()}


check(manifest(a) == manifest(b), "two builds differ")
check(manifest(a / "variants") == manifest(here / "variants"), "default build differs from a fresh build")
check(len(manifest(a / "variants")) > 0, "empty build")

mapping = json.loads((a / "variant-map.json").read_text(encoding="utf-8"))
catalog = {"D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "C0", "C1"}
check(sorted(v["id"] for v in mapping.values()) == sorted(catalog), f"map ids {sorted(v['id'] for v in mapping.values())}")
dirs = {p.name for p in (a / "variants").iterdir()}
check(dirs == set(mapping), "variant dirs do not match the map")

pages = {}
for vid, info in mapping.items():
    page = (a / "variants" / vid / "index.html").read_bytes()
    check(re.fullmatch(r"[0-9a-f]{12}", vid) is not None, f"{vid}: id is not 12 hex digits")
    check(hashlib.sha256(page).hexdigest()[:12] == vid, f"{vid}: id is not the page hash")
    pages[info["id"]] = page.decode("utf-8")

base = (here / "site" / "index.html").read_text(encoding="utf-8")
check(pages["C0"] == base, "C0 is not the base page")
for did, page in pages.items():
    if did != "C0":
        check(page != base, f"{did}: page equals the base")

leaks = re.compile(
    r"\b[DC][0-9]\b|overlap|clip|contrast|missing|shift|off-by-one|misalign|off-viewport|console|defect|benign|control",  # portability-ok: Python re in a heredoc, not grep or sed
    re.IGNORECASE,
)
for path in sorted(p for p in (a / "variants").rglob("*")):
    rel = path.relative_to(a / "variants").as_posix()
    check(not leaks.search(rel), f"path names a defect: {rel}")
    if path.name == "index.html":
        hit = leaks.search(path.read_text(encoding="utf-8"))
        check(hit is None, f"{rel}: markup names a defect: {hit.group(0) if hit else ''}")
for path in [here / "site" / "index.html", *(a / "variants").rglob("index.html")]:
    text = path.read_text(encoding="utf-8")
    check(re.search(r"\bDate\b|Math\.random", text) is None, f"{path}: uses Date or Math.random")  # portability-ok: Python re in a heredoc, not grep or sed


def luminance(hex_color):
    channels = [int(hex_color[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(fg, bg="#ffffff"):
    hi, lo = sorted((luminance(fg), luminance(bg)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def px(pattern, page):
    match = re.search(pattern, page)
    return int(match.group(1)) if match else 0


def srcs(page):
    return re.findall(r'<img src="([^"]+)" alt="[^"]+"', page)


p = pages
check("@media (max-width: 375px)" in p["D1"] and "position: absolute" in p["D1"], "D1: no badge overlap at 375")
check("position: absolute" not in base, "base already positions the badge absolutely")
check(re.search(r"width:\s*64px;\s*overflow:\s*hidden;\s*white-space:\s*nowrap", p["D2"]) is not None, "D2: no clipped button")  # portability-ok: Python re in a heredoc, not grep or sed
body = re.search(r"body \{[^}]*color: (#[0-9a-f]{6}); background: (#[0-9a-f]{6})", p["D3"])
check(body is not None and body.group(1) == "#a0a0a0" and contrast(body.group(1), body.group(2)) <= 3.0, "D3: body text not <= 3:1")
check(contrast("#222222") >= 4.5, "base body text is not readable")
for did, page in p.items():
    for src in srcs(page):
        vid = next(k for k, v in mapping.items() if v["id"] == did)
        exists = (a / "variants" / vid / src).is_file()
        check(exists == (did != "D4" or src == "img/card.png"), f"{did}: image {src} exists={exists}")
check(len(srcs(p["D4"])) == 3 and any(s != "img/card.png" for s in srcs(p["D4"])), "D4: no image points at an absent file")
check("setTimeout(" in p["D5"] and "}, 300);" in p["D5"] and px(r"height: (\d+)px; line-height", p["D5"]) == 48, "D5: no 48 px late insert")
check(p["D6"].count("Showing 5 results") == 1 and p["D6"].count("<li>") == 4, "D6: count does not overstate the rows by one")
check(base.count("<li>") == 5, "base does not render 5 rows")
check('document.querySelector(".cart-count").textContent' in p["D7"] and "cart-count\"" not in p["D7"].split("<script>")[0], "D7: click does not dereference an absent element")
check(p["D7"].index("toast.hidden = false;") < p["D7"].index(".cart-count"), "D7: toast is not shown before the throw")
check(px(r"\.save \{ margin-top: (\d+)px", p["D8"]) >= 8, "D8: misalignment under 8 px")
check(px(r"\.specs \{[^}]*width: (\d+)px", p["D9"]) - 375 >= 8, "D9: table does not overflow 375 by 8 px")
h1 = re.search(r"h1 \{[^}]*color: (#[0-9a-f]{6})", p["C1"]).group(1)
check(h1 != "#1a1a1a" and contrast(h1) >= 4.5, f"C1: heading color {h1} not a readable change")

if errors:
    print("\n".join(f"FAIL: {e}" for e in errors), file=sys.stderr)
    sys.exit(1)
print(f"PASS: {len(mapping)} variants")
PY
