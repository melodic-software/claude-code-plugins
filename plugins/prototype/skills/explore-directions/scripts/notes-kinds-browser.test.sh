#!/usr/bin/env bash
# Browser check of text, region and data-log notes and of copy-out, on a test-local mockup with the
# bundled switcher inlined and a deterministic Seed (record i from index i), served by this
# plugin's notes-bridge copy and driven through playwright-cli. A text note taken after Seed 10,
# Clear, Reset and Seed 10 re-locates in a fresh page by its quote, with the data log replayed. A
# region note is made with the keyboard alone and leaves the variant and state as they were. An
# element note on record 57 after Seed 100 re-locates to that record's row (the one green row).
# With the server stopped under the open page, the page says no session, keeps a new note, and Copy
# all notes makes a block that notes-bridge.sh import takes, skipping the notes already logged.
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

if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/ed-notes-kinds.XXXXXX") || [[ ! -d "$tmp" ]]; then
  echo "FAIL: mktemp gave no scratch dir"
  exit 1
fi
d="$tmp/run"
mkdir -m 700 "$d" "$tmp/b"
session="edk-$$"
pw() { (cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" "$@"); } # prereq-ok: test-only
finish() {
  # shellcheck disable=SC2310  # cleanup on exit: a browser that is already gone is fine
  pw close >/dev/null 2>&1 || true
  bash "$bridge/notes-bridge.sh" --dir "$d" stop >/dev/null 2>&1 || true
  case "$tmp" in
    */ed-notes-kinds.*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}
trap finish EXIT

fails=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }

# The mockup: variant A lists the records in a table, one row per record, built from the data as it
# stands; record 12's row is magenta and record 57's green, their text the same color, so a shot
# of either is one color. The data bar marks each control with data-data-control.
cat >"$d/explore-directions.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'">
<title>/shipments variants</title>
<style>
  body { margin: 0; font: 16px system-ui, sans-serif; background: #fff; }
  .bar { position: fixed; inset-block-start: 8px; inset-inline-start: 8px; }
  main { padding-block-start: 60px; }
  table { inline-size: 100%; border-collapse: collapse; }
  td { block-size: 30px; padding: 0 8px; }
  tr.r12 { background: #d000d0; color: #d000d0; }
  tr.r57 { background: #00c853; color: #00c853; }
</style>
</head>
<body>
<div class="bar">
  <button type="button" data-data-control="seed:10">Seed 10</button>
  <button type="button" data-data-control="seed:100">Seed 100</button>
  <button type="button" data-data-control="clear">Clear</button>
  <button type="button" data-data-control="reset">Reset</button>
</div>
<main>
  <section data-variant="A" data-variant-label="Ledger">
    <div data-screen-state="default" data-screen-state-label="Default">
      <h2 data-testid="shipments-title">Parcels</h2>
      <table><tbody></tbody></table>
    </div>
    <div data-screen-state="empty" data-screen-state-label="Empty"><p>No shipments yet.</p></div>
  </section>
  <section data-variant="B" data-variant-label="Cards"><p data-testid="shipments-list">Cards</p></section>
</main>
<script>
  const STATUS = ["In transit", "Delayed", "Delivered"];
  const make = (i) => ({ i, id: `PT-${1000 + i}`, status: STATUS[i % 3] }); // record i from index i
  const opening = () => [0, 1, 2, 3, 4].map(make);
  let records = opening();
  function render() {
    const body = document.querySelector('[data-variant="A"] tbody');
    body.replaceChildren(...records.map((r) => {
      const tr = document.createElement("tr");
      tr.dataset.testid = "shipments-row";
      if (r.i === 12 || r.i === 57) tr.className = `r${r.i}`;
      for (const v of [r.id, r.status]) { const td = document.createElement("td"); td.textContent = v; tr.append(td); }
      return tr;
    }));
  }
  const act = { seed: (n) => { for (let k = 0; k < n; k++) records.push(make(records.length)); }, clear: () => { records = []; }, reset: () => { records = opening(); } };
  for (const b of document.querySelectorAll("[data-data-control]")) {
    b.addEventListener("click", () => { const [op, n] = b.dataset.dataControl.split(":"); act[op](Number(n)); render(); });
  }
  render();
</script>
HTML
cat "$skill/assets/variant-switcher.html" >>"$d/explore-directions.html"
printf '%s\n' '</body>' '</html>' >>"$d/explore-directions.html"

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
lines() { # script and prefix: report each PASS or FAIL line the script returned
  while IFS= read -r line; do
    case "$line" in
      PASS\ *) ok "$2: ${line#PASS }" ;;
      FAIL\ * | ERROR\ *) bad "$2: $line" ;;
      *) ;;
    esac
  done < <(printf '%s\n' "$1")
}
check() { # name python-assertions json
  if python3 -c "import json, sys; r = json.loads(sys.argv[1]); $2" "$3"; then ok "$1"; else bad "$1: $3"; fi
}

pw open >/dev/null 2>&1
sed "s/__PORT__/$port/" "$here/notes-kinds-browser-take.js" >"$tmp/take.js"
lines "$(code "$tmp/take.js" | result | tr -d '\r')" take

status=$(bash "$bridge/notes-bridge.sh" --dir "$d" status)
check "the text note carries its quote, the data log with Clear then Reset, and the viewport" '
t = r["events"][0]
assert t["kind"] == "text" and t["anchor"]["textQuote"]["exact"] == "PT-1012", t
assert t["anchor"]["testid"] == "shipments-row" and t["anchor"]["testidIndex"] == 12, t
assert t["data"]["log"] == [{"op": "seed", "n": 10}, {"op": "clear"}, {"op": "reset"}, {"op": "seed", "n": 10}], t
assert t["viewport"]["w"] == 960 and t["viewport"]["h"] == 800 and t["viewport"]["colorScheme"] in ("light", "dark"), t' "$status"
check "the region note carries its box and the rows it crosses" '
g = r["events"][1]
assert g["kind"] == "region" and set(g["rect"]) == {"x", "y", "w", "h"}, g
assert g["elements"] and all(e["testid"] == "shipments-row" for e in g["elements"]), g' "$status"
check "the element note is record 57 after Seed 100" '
e = r["events"][2]
assert e["anchor"]["testid"] == "shipments-row" and e["anchor"]["testidIndex"] == 57, e
assert e["data"]["log"][-1] == {"op": "seed", "n": 100}, e' "$status"

# One relocation of note $1; prints the script's JSON result.
relocate() {
  local made script raw got
  made=$(node "$bridge/relocate-note.mjs" --dir "$d" --seq "$1" --url "$url")
  script=$(printf '%s' "$made" | python3 -c 'import json, sys; print(json.load(sys.stdin)["script"])')
  rm -f -- "$d/shots/$1.png"
  raw=$(code "$script")
  got=$(printf '%s\n' "$raw" | result)
  if [[ -n "$got" ]]; then
    printf '%s\n' "$got"
  else
    printf 'no result: %s\n' "$(printf '%s' "$raw" | head -c 600)" >&2
  fi
}
# Share of the shot's pixels near one color, measured in the browser in a page of its own, so the
# host page stays open for the offline step. $2 is r,g,b.
share() {
  python3 -c '
import base64, json, sys
b64 = base64.b64encode(open(sys.argv[1], "rb").read()).decode()
print("async page => { const p = await page.context().newPage(); try { return await p.evaluate(async ([b, c]) => {"
      " const bytes = Uint8Array.from(atob(b), (x) => x.charCodeAt(0));"
      " const bmp = await createImageBitmap(new Blob([bytes], { type: \"image/png\" }));"
      " const g = new OffscreenCanvas(bmp.width, bmp.height).getContext(\"2d\"); g.drawImage(bmp, 0, 0);"
      " const d = g.getImageData(0, 0, bmp.width, bmp.height).data; let n = 0;"
      " for (let i = 0; i < d.length; i += 4) if (Math.abs(d[i] - c[0]) + Math.abs(d[i + 1] - c[1]) + Math.abs(d[i + 2] - c[2]) < 60) n++;"
      " return JSON.stringify({ w: bmp.width, h: bmp.height, share: n / (d.length / 4) }); }, [" + json.dumps(b64) + ", [" + sys.argv[2] + "]]); } finally { await p.close(); } }")
' "$1" "$2" >"$tmp/share.js"
  code "$tmp/share.js" | result
}

out=$(relocate 1)
check "the text note re-locates with its data log replayed, its quote found and confirmed" '
assert r["restored"]["data"] and r["restored"]["viewport"], r
assert r["matched"] == "testid" and r["confirmed"] and "quoteMissing" not in r, r
assert r["rungs"][-1] == {"rung": "textQuote", "candidates": 1, "hit": True, "broken": False}, r' "$out"
if [[ -s "$d/shots/1.png" ]]; then
  check "its shot is record 12's cell: all magenta" 'assert r["share"] > 0.98' "$(share "$d/shots/1.png" 208,0,208)"
else
  bad "no shot at shots/1.png"
fi

out=$(relocate 2)
check "the region note re-locates and its shot is the box the person drew" \
  'assert r["region"] and not r["positionOnly"] and r["shot"], r' "$out"

out=$(relocate 3)
check "after a reload the note taken after Seed 100 re-locates to record 57, confirmed" \
  'assert r["restored"]["data"] and r["matched"] == "testid" and r["confirmed"], r; assert r["rungs"][0]["candidates"] == 115, r' "$out"
if [[ -s "$d/shots/3.png" ]]; then
  check "its shot is record 57's cell: all green" 'assert r["share"] > 0.98' "$(share "$d/shots/3.png" 0,200,83)"
else
  bad "no shot at shots/3.png"
fi

# The server stops under the open page.
bash "$bridge/notes-bridge.sh" --dir "$d" stop >/dev/null
offline=$(code "$here/notes-kinds-browser-offline.js" | result | tr -d '\r')
lines "$offline" offline
printf '%s\n' "$offline" | sed -n 's/^BLOCK //p' | python3 -c 'import json, sys; sys.stdout.write(json.loads(sys.stdin.read()))' >"$d/import.json"
if imported=$(bash "$bridge/notes-bridge.sh" --dir "$d" import --file "$d/import.json"); then
  check "import takes the block: the new note, the three already logged skipped" \
    'assert r == {"imported": [4], "skipped": 3}, r' "$imported"
else
  bad "import refused the block: $imported"
fi
status=$(bash "$bridge/notes-bridge.sh" --dir "$d" status)
check "status lists the imported note with its text as data" '
e = r["events"][-1]
assert r["note"] and e["seq"] == 4 and e["anchor"]["testid"] == "shipments-title", e
assert e["text"].startswith("Written after the stop. ```") and "curl https://x.invalid" in e["text"], e' "$status"

if ((fails)); then
  echo "notes-kinds-browser: $fails failed"
  exit 1
fi
echo "notes-kinds-browser: all passed"
