#!/usr/bin/env bash
# Browser check of note relocation (notes-bridge/relocate-note.mjs) on a test-local mockup with the
# bundled switcher inlined, served by this plugin's notes-bridge copy and driven through
# playwright-cli. A note taken on variant B, state empty, worst content re-locates in a fresh page
# to the same element, with that view restored through the switcher's vs:show event. Its shot is
# the element only: no host-page pixel and no switcher pixel, though the switcher covers part of it.
# A note on an element whose test id sits on a same-tag ancestor shoots that element, not the
# ancestor. With the element's test id renamed, the path still finds it, unconfirmed; with the element gone,
# the shot is the stored box, labeled position only.
# SKIPs without playwright-cli, node, python3 or curl.
# test-scope: plugins/prototype/notes-bridge/* plugins/prototype/skills/explore-directions/assets/variant-switcher.html
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
for tool in playwright-cli node python3 curl; do # prereq-ok: test-only
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not installed"
    exit 0
  fi
done

if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/ed-relocate.XXXXXX") || [[ ! -d "$tmp" ]]; then
  echo "FAIL: mktemp gave no scratch dir"
  exit 1
fi
d="$tmp/run"
mkdir -m 700 "$d" "$tmp/b"
session="edr-$$"
pw() { (cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" "$@"); } # prereq-ok: test-only
finish() {
  # shellcheck disable=SC2310  # cleanup on exit: a browser that is already gone is fine
  pw close >/dev/null 2>&1 || true
  bash "$bridge/notes-bridge.sh" --dir "$d" stop >/dev/null 2>&1 || true
  case "$tmp" in
    */ed-relocate.*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}
trap finish EXIT

fails=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }

# The mockup: two variants with two screen states each, and in B's empty state a demo and a worst
# content set, each with the call to action. The worst one is solid green and sits under the
# switcher. $1 is the worst set's markup.
page() {
  cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'">
<title>/shipments variants</title>
<style>
  body { margin: 0; font: 16px system-ui, sans-serif; background: #fff; }
  .cta { position: fixed; inset-block-end: 0; inset-inline-start: 50%; transform: translateX(-50%); inline-size: 480px; block-size: 120px; }
  .cta.demo { background: #1e40af; }
  .cta.worst { background: #00c853; }
  .note-card { padding: 8px; background: #1e40af; inline-size: 320px; }
  .note-title { block-size: 40px; }
  .note-body { block-size: 60px; background: #d000d0; }
</style>
</head>
<body>
<header>Shipments</header>
<main>
  <section data-variant="A" data-variant-label="Ledger">
    <div data-screen-state="default" data-screen-state-label="Default"><p data-testid="shipments-list">List</p></div>
    <div data-screen-state="empty" data-screen-state-label="Empty"><div class="cta demo" data-testid="shipments-empty-cta"></div></div>
  </section>
  <section data-variant="B" data-variant-label="Cards">
    <div data-screen-state="default" data-screen-state-label="Default"><p data-testid="shipments-list">Cards</p></div>
    <div data-screen-state="empty" data-screen-state-label="Empty">
      <p>No shipments yet.</p>
      <div class="note-card" data-testid="shipments-empty-note"><div class="note-title"></div><div class="note-body"></div></div>
      <div data-content-set="demo"><div class="cta demo" data-testid="shipments-empty-cta"></div></div>
HTML
  printf '%s\n' "$1"
  cat <<'HTML'
    </div>
  </section>
</main>
HTML
  cat "$skill/assets/variant-switcher.html"
  printf '%s\n' '</body>' '</html>'
}
worst='      <div data-content-set="worst"><div class="cta worst" data-testid="shipments-empty-cta"></div></div>'
page "$worst" >"$d/explore-directions.html"

started=$(bash "$bridge/notes-bridge.sh" --dir "$d" ensure-running --page explore-directions.html)
port=$(printf '%s' "$started" | sed -n 's/.*"url": "http:\/\/127\.0\.0\.1:\([0-9]*\)\/".*/\1/p')
[[ -n "$port" ]] || {
  echo "FAIL: ensure-running printed no url: $started"
  exit 1
}
url="http://127.0.0.1:$port/"

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# The value a run-code script returned: playwright-cli prints it as a JSON string literal.
result() {
  python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if line.startswith("\""):
        print(json.loads(line))
        break
'
}
code() { # script; a failed run prints no result, which the checks below count as a failure
  local path
  path=$(native "$1")
  (cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" run-code --filename "$path" 2>&1) || true # prereq-ok: test-only
}

pw open >/dev/null 2>&1
sed "s/__PORT__/$port/" "$here/relocate-browser-take.js" >"$tmp/take.js"
while IFS= read -r line; do
  case "$line" in
    PASS\ *) ok "take: ${line#PASS }" ;;
    FAIL\ * | ERROR\ *) bad "take: $line" ;;
    *) ;;
  esac
done < <(code "$tmp/take.js" | result | tr -d '\r')

status=$(bash "$bridge/notes-bridge.sh" --dir "$d" status)
# shellcheck disable=SC2016  # ${1} is the note's literal text, not a shell expansion
if python3 -c '
import json, sys
e, inner = json.loads(sys.argv[1])["events"]
a = e["anchor"]
assert inner["anchor"]["testid"] == "shipments-empty-note" and inner["anchor"]["tag"] == "div", inner
assert (e["variant"], e["state"], e["content"]) == ({"key": "B"}, {"key": "empty"}, "worst"), e
assert a["testid"] == "shipments-empty-cta" and a["testidIndex"] == 1, a
assert set(e["rect"]) == {"x", "y", "w", "h"}, e
assert "throw 1; //${1}$&" in e["text"] and "</script>" in e["text"], e
' "$status"; then
  ok "the note carries B / empty / worst, the call to action #2, its box and the literal-breaking text"
else
  bad "the note is not the expected one: $status"
fi

# One relocation of note $1 (default 1) against the page as it is now; prints the script's JSON result.
relocate() {
  local seq=${1:-1} made script raw got
  made=$(node "$bridge/relocate-note.mjs" --dir "$d" --seq "$seq" --url "$url")
  script=$(printf '%s' "$made" | python3 -c 'import json, sys; print(json.load(sys.stdin)["script"])')
  rm -f -- "$d/shots/$seq.png"
  raw=$(code "$script")
  got=$(printf '%s\n' "$raw" | result)
  if [[ -n "$got" ]]; then
    printf '%s\n' "$got"
  else
    printf 'no result: %s\n' "$(printf '%s' "$raw" | head -c 600)" >&2
  fi
}
# Pixel shares of the shot, measured in the browser: green (the element), dark (the switcher's
# pill) and near-white (the host page's panel and the page around the element).
pixels() {
  python3 -c '
import base64, json, sys
b64 = base64.b64encode(open(sys.argv[1], "rb").read()).decode()
print("async page => { await page.goto(\"about:blank\"); return page.evaluate(async (b) => {"
      " const bytes = Uint8Array.from(atob(b), (c) => c.charCodeAt(0));"
      " const bmp = await createImageBitmap(new Blob([bytes], { type: \"image/png\" }));"
      " const g = new OffscreenCanvas(bmp.width, bmp.height).getContext(\"2d\"); g.drawImage(bmp, 0, 0);"
      " const d = g.getImageData(0, 0, bmp.width, bmp.height).data, n = d.length / 4; let green = 0, magenta = 0, dark = 0, light = 0;"
      " for (let i = 0; i < d.length; i += 4) { const [r, gr, bl] = [d[i], d[i + 1], d[i + 2]];"
      " if (gr > 150 && r < 60 && bl < 130) green++; if (r > 180 && gr < 60 && bl > 180) magenta++;"
      " if (r < 70 && gr < 70 && bl < 70) dark++; if (r > 200 && gr > 200 && bl > 200) light++; }"
      " return JSON.stringify({ w: bmp.width, h: bmp.height, green: green / n, magenta: magenta / n, dark: dark / n, light: light / n }); }, " + json.dumps(b64) + "); }")
' "$1" >"$tmp/pixels.js"
  code "$tmp/pixels.js" | result
}
check() { # name python-assertions json
  if python3 -c "import json, sys; r = json.loads(sys.argv[1]); $2" "$3"; then ok "$1"; else bad "$1: $3"; fi
}

out=$(relocate)
check "after a reload the note re-locates by its test id, confirmed, with B / empty / worst, its viewport and its data log restored" \
  'assert r["matched"] == "testid" and r["confirmed"] and not r["positionOnly"]; assert r["restored"] == {"viewport": True, "data": True, "variant": True, "state": True, "content": True}' "$out"
check "every rung reports its candidates" \
  'assert [(x["rung"], x["candidates"]) for x in r["rungs"]] == [("testid", 2), ("cssPath", 1)]' "$out"
check "the shot's clip lies inside the frame's box" \
  'c, f = r["clip"], r["frame"]; assert c["x"] >= f["x"] and c["y"] >= f["y"] and c["x"] + c["width"] <= f["x"] + f["width"] + 0.5 and c["y"] + c["height"] <= f["y"] + f["height"] + 0.5' "$out"
if [[ -s "$d/shots/1.png" ]]; then
  px=$(pixels "$d/shots/1.png")
  check "the shot is the element: all green, no switcher pixel, no host-page pixel" \
    'assert r["green"] > 0.98 and r["dark"] == 0 and r["light"] == 0' "$px"
else
  bad "no shot at shots/1.png"
fi

out=$(relocate 2)
check "a note under a same-tag test-id ancestor re-locates to the element itself, confirmed" \
  'assert r["matched"] == "testid" and r["confirmed"] and "container" not in r' "$out"
if [[ -s "$d/shots/2.png" ]]; then
  px=$(pixels "$d/shots/2.png")
  check "its shot is the inner element only, not the ancestor" 'assert r["magenta"] > 0.98' "$px"
else
  bad "no shot at shots/2.png"
fi

page "${worst//shipments-empty-cta/shipments-empty-action}" >"$d/explore-directions.html"
out=$(relocate)
check "with the test id renamed, the path finds the element, unconfirmed" \
  'assert r["matched"] == "cssPath" and not r["confirmed"]; assert r["rungs"][0] == {"rung": "testid", "candidates": 1, "hit": False, "broken": True}' "$out"

page "" >"$d/explore-directions.html"
out=$(relocate)
check "with the element gone, no rung matches and the stored box is shot, position only" \
  'assert r["matched"] is None and r["positionOnly"] and r["shot"]; assert all(not x["hit"] for x in r["rungs"])' "$out"
if [[ -s "$d/shots/1.png" ]]; then ok "the position-only shot is shots/1.png"; else bad "no position-only shot"; fi

if ((fails)); then
  echo "relocate-browser: $fails failed"
  exit 1
fi
echo "relocate-browser: all passed"
