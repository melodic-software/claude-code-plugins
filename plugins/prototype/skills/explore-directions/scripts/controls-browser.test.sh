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

if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/ed-controls.XXXXXX") || [[ ! -d "$tmp" ]]; then
  echo "FAIL: mktemp gave no scratch dir"
  exit 1
fi
d="$tmp/run"
mkdir -m 700 "$d" "$tmp/b"
session="edc-$$"
pw() { (cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" "$@"); } # prereq-ok: test-only
finish() {
  # shellcheck disable=SC2310  # cleanup on exit: a browser that is already gone is fine
  pw close >/dev/null 2>&1 || true
  bash "$bridge/notes-bridge.sh" --dir "$d" stop >/dev/null 2>&1 || true
  case "$tmp" in
    */ed-controls.*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}
trap finish EXIT

fails=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }

# The fixture with the controls runtime and the switcher inlined; $1 replaces "--card-gap" as the
# first control's target, and $2, when given, replaces the manifest's opening line.
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
check() { # name python-assertions json
  if python3 -c "import json, sys; r = json.loads(sys.argv[1]); $2" "$3"; then ok "$1"; else bad "$1: $3"; fi
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
