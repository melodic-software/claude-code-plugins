#!/usr/bin/env bash
# test-scope: plugins/prototype/notes-bridge/*
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
# shellcheck source=../../../lib/browser-test-helpers.sh
source "$here/../../../lib/browser-test-helpers.sh"
browser_setup ed-notes-region edr playwright-cli python3 curl

{
  cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'">
<title>All candidates</title>
<style>
  body { margin: 0; font: 16px system-ui, sans-serif; background: #fff; }
  ul { margin: 0; padding: 40px 0; list-style: none; }
  li { block-size: 100px; border-block-end: 1px solid #ccc; box-sizing: border-box; }
</style>
</head>
<body>
<main>
  <h1 data-testid="candidates-title">All candidates</h1>
  <ul>
HTML
  for i in $(seq 1 40); do printf '    <li data-testid="candidate">Candidate %s</li>\n' "$i"; done
  printf '%s\n' '  </ul>' '</main>' '</body>' '</html>'
} >"$d/explore-directions.html"

browser_serve

pw open >/dev/null 2>&1
sed "s/__PORT__/$port/" "$here/notes-region-browser-take.js" >"$tmp/take.js"
out=$(code "$tmp/take.js" | result | tr -d '\r')
n=0
while IFS= read -r line; do
  case "$line" in
    PASS\ *) n=$((n + 1)); ok "take: ${line#PASS }" ;;
    FAIL\ * | ERROR\ *) n=$((n + 1)); bad "take: $line" ;;
    *) ;;
  esac
done < <(printf '%s\n' "$out")
((n > 0)) || bad "take: no results ($(printf '%s' "$out" | head -c 1500))"
status=$(bash "$bridge/notes-bridge.sh" --dir "$d" status)
facts=$(python3 -c '
import json, sys
fact = lambda tag: next((json.loads(l[len(tag) + 1:]) for l in sys.argv[2].splitlines() if l.startswith(tag + " ")), None)
print(json.dumps({"log": json.loads(sys.argv[1]), "geom": fact("GEOM"), "draft": fact("DRAFT"), "seeded": fact("SEEDED")}))
' "$status" "$out")
check "the region note, then two changes naming it, are in the log" '
e = r["log"]["events"]
assert [x["seq"] for x in e] == [1, 2, 3], e
assert e[0]["kind"] == "region" and "change" not in e[0], e
assert [x["change"] for x in e[1:]] == [1, 1], e' "$facts"
check "the region drawn past the frame's bottom edge is taller than the frame" '
g, b = r["geom"], r["seeded"]
assert b[3] > g["viewH"], (b, g)' "$facts"
check "the note was sent with the box its draft was moved to" '
assert r["draft"] and r["seeded"] and all(abs(a - b) < 1 for a, b in zip(r["draft"], r["seeded"])), (r["draft"], r["seeded"])' "$facts"
check "dragging the sent region moved it 150 pixels down, its size unchanged" '
g, b, m = r["geom"], r["seeded"], r["log"]["events"][1]["rect"]
assert abs(m["y"] / 100 * g["pageH"] - (b[1] + 150)) < 2, (m, b, g)
assert abs(m["h"] / 100 * g["pageH"] - b[3]) < 2, (m, b, g)' "$facts"
check "Shift and the down arrow grew it 20 pixels, and the note's rect in the log is the last change's" '
g, e = r["geom"], r["log"]["events"]
assert e[0]["rect"] == e[2]["rect"], e
assert abs((e[2]["rect"]["h"] - e[1]["rect"]["h"]) / 100 * g["pageH"] - 20) < 2, e' "$facts"

if ((fails)); then
  echo "notes-region-browser: $fails failed"
  exit 1
fi
echo "notes-region-browser: all passed"
