#!/usr/bin/env bash
# Browser check of the notes host's Controls tab (notes-bridge/host.html) and the controls runtime
# (notes-bridge/controls.js) on the controls-mockup eval fixture, with the switcher and the runtime
# inlined, served by this plugin's notes-bridge copy and driven through playwright-cli. The dock's
# two tabs work by keyboard; each control type writes its CSS variable or attribute in the framed
# mockup and shows its value; Copy config copies them; a note carries every manifest id; the
# built-in Seed and content entries press the page's own controls; Reset controls restores the
# defaults and leaves the data alone; the note re-locates with its controls restored. A manifest
# outside controls.schema.json is refused whole. Opened alone from file://, the page draws its own
# panel from the same manifest.
# SKIPs without playwright-cli, node, python3 or curl.
# test-scope: plugins/prototype/notes-bridge/* plugins/prototype/skills/explore-directions/assets/variant-switcher.html plugins/prototype/.claude-plugin/plugin.json
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
# shellcheck source=../../../lib/browser-test-helpers.sh
source "$here/../../../lib/browser-test-helpers.sh"
browser_setup ed-controls edc playwright-cli node python3 curl

page() {
  local runtime='<!-- The canonical lib/ui-feedback/controls.js is inlined whole here; elided from this fixture. -->'
  local switcher='<!-- The bundled assets/variant-switcher.html is inlined whole here; elided from this fixture. -->'
  local head='{"controls": ['
  while IFS= read -r line; do
    if [[ "$line" == "$runtime" ]]; then
      printf '<script>\n'
      cat "$bridge/controls.js"
      printf '</script>\n'
    elif [[ "$line" == "$switcher" ]]; then
      cat "$skill/assets/variant-switcher.html"
    elif [[ "$line" == "$head" && -n "${2:-}" ]]; then
      printf '%s\n' "$2"
    else printf '%s\n' "${line/\"target\": \"--card-gap\"/\"target\": \"$1\"}"; fi
  done <"$skill/evals/fixtures/controls-mockup.html" >"$d/explore-directions.html"
}
page "--card-gap"

browser_serve
url="http://127.0.0.1:$port/"

# Run one page script with __PORT__, __FILE__, __WANT__ ($3) and __REGISTRY__ (the registry cases
# of lib/ui-feedback/fixtures/controls.json, as a JSON literal) filled in, and grade each line it returns.
run() { # script label [want]
  local n=0 line
  python3 -c '
import json, sys
src, dst, port, page, want, fixtures = sys.argv[1:]
text = open(src, encoding="utf-8").read()
registry = json.dumps(json.load(open(fixtures, encoding="utf-8"))["registry"])
for k, v in {"PORT": port, "FILE": "file://" + page, "WANT": want, "REGISTRY": registry}.items():
    text = text.replace(f"__{k}__", v)
open(dst, "w", encoding="utf-8").write(text)
' "$1" "$tmp/$2.js" "$port" "$d/explore-directions.html" "${3:-}" "$skill/../../../../lib/ui-feedback/fixtures/controls.json"
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      PASS\ *) ok "$2: ${line#PASS }" ;;
      *) bad "$2: $line" ;;
    esac
  done < <(code "$tmp/$2.js" | result | tr -d '\r' | grep -E '^(PASS|FAIL|ERROR) ')
  ((n > 0)) || bad "$2: no results"
}

pw open >/dev/null 2>&1
run "$here/controls-browser-take.js" take

status=$(bash "$bridge/notes-bridge.sh" --dir "$d" status)
check "the bridge stored the note with every manifest id and its value" \
  'e = r["events"][0]; assert e["controls"] == {"card-gap": "24", "accent": "#aa3300", "font": "Georgia, serif", "dense": "on", "align": "center"}, e' "$status"

made=$(node "$bridge/relocate-note.mjs" --dir "$d" --seq 1 --url "$url")
script=$(printf '%s' "$made" | python3 -c 'import json, sys; print(json.load(sys.stdin)["script"])')
out=$(code "$script" | result)
check "after a reload the note re-locates with its data log and its controls restored" \
  'assert r["matched"] == "testid" and r["confirmed"], r; assert r["restored"]["controls"] is True and r["restored"]["data"] is True, r["restored"]' "${out:-null}"

page "onclick"
run "$here/controls-browser-refuse.js" refuse

page "--card-gap" '{"controls": [,'
run "$here/controls-browser-status.js" unparsed "is not JSON"

page "--card-gap" '{"controls": [{"id": "tint", "label": "Tint", "group": "color", "type": "color", "target": "--tint", "default": "oklch(0.6 0.1 180)"},'
run "$here/controls-browser-status.js" misfit "tint: its field cannot hold its default"

page "--card-gap"
run "$here/controls-browser-alone.js" alone

page "--card-gap" '{"placement": "top-left", "controls": ['
run "$here/controls-browser-corner.js" corner

if ((fails)); then
  echo "controls-browser: $fails failed"
  exit 1
fi
echo "controls-browser: all passed"
