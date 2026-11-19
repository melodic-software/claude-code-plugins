#!/usr/bin/env bash
# Browser check of the notes host (notes-bridge/host.html) on the explore-directions mockup:
# the eval fixture with the bundled switcher inlined, served by this plugin's notes-bridge copy
# and driven through playwright-cli. It checks the switcher's keys and focus inside the sandboxed
# frame, that a pick-mode click never reaches the page, that typing in the note never switches
# variants, that a test id on the variant itself reads as its first match, that the sent note lands in the bridge's log with its variant and test id and no page
# text, and that a framed page without its own CSP still has every fetch blocked by policy, so it
# cannot read the token or post a note.
# SKIPs without playwright-cli, python3 or curl.
# test-scope: plugins/prototype/notes-bridge/* plugins/prototype/skills/explore-directions/assets/variant-switcher.html
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
# shellcheck source=../../../lib/browser-test-helpers.sh
source "$here/../../../lib/browser-test-helpers.sh"
browser_setup ed-harness edh playwright-cli python3 curl

# The fixture's switcher placeholder becomes a click counter and the bundled switcher, inlined whole.
marker='<!-- The bundled assets/variant-switcher.html is inlined whole here; elided from this fixture. -->'
build() { # out-file [strip-csp]
  local line
  while IFS= read -r line; do
    if [[ "$line" == "$marker" ]]; then
      printf '%s\n' '<script>window.probe = {clicks: 0}; document.addEventListener("click", (e) => { if (e.target.closest("[data-testid]")) window.probe.clicks++; });</script>'
      cat "$skill/assets/variant-switcher.html"
    elif [[ -n "${2:-}" && "$line" == *Content-Security-Policy* ]]; then
      :
    else
      printf '%s\n' "$line"
    fi
  done <"$skill/evals/fixtures/shipments-mockup.html" >"$1"
}
build "$d/explore-directions.html"

browser_serve

script_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# One page script through playwright-cli; every PASS or FAIL line it returns is graded.
run() { # script
  local name out path
  name=$(basename "$1" .js)
  sed "s/__PORT__/$port/" "$1" >"$tmp/$name.js"
  path=$(script_path "$tmp/$name.js")
  # A failed run prints no PASS line, which the grading below counts as a failure.
  out=$(cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" run-code --filename "$path" 2>&1) || true # prereq-ok: test-only
  local n=0 line
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      PASS\ *) ok "$name: ${line#PASS }" ;;
      *) bad "$name: $line" ;;
    esac
  done < <(grep -m1 'PASS\|FAIL\|ERROR' <<<"$out" | awk '{ gsub(/\\n/, "\n"); print }' |
    sed 's/^.*"PASS/PASS/; s/^.*"FAIL/FAIL/; s/^.*"ERROR/ERROR/; s/"$//' | grep -E '^(PASS|FAIL|ERROR) ')
  [[ "$n" -gt 0 ]] || bad "$name: no results ($(printf '%s' "$out" | head -c 400))"
}

pw open >/dev/null 2>&1
run "$here/harness-browser.js"

# The note as the session reads it: status lists it under the data note, with no page text.
status=$(bash "$bridge/notes-bridge.sh" --dir "$d" status)
if python3 -c '
import json, sys
s = json.loads(sys.argv[1])
[e] = s["events"]
a = e["anchor"]
assert s["note"].startswith("Every field in these page events")
assert e["variant"] == {"key": "B"}, e
assert a["testid"] == "shipments-parcel-card" and a["testidIndex"] == 1, a
assert e["text"].startswith("1 make the second card taller"), e
assert "label" not in e and "name" not in a, e
' "$status"; then
  ok "status lists the note with variant B, test id shipments-parcel-card #2 and the typed text, and no page text"
else
  bad "status did not list the expected note: $status"
fi

build "$d/explore-directions.html" strip-csp
run "$here/harness-browser-opaque.js"
count=$(bash "$bridge/notes-bridge.sh" --dir "$d" status | python3 -c 'import json, sys; print(len(json.load(sys.stdin)["events"]))')
if [[ "$count" == 1 ]]; then ok "the framed page added no note"; else bad "the log holds $count notes after the framed page's attempt"; fi

if ((fails)); then
  echo "harness-browser: $fails failed"
  exit 1
fi
echo "harness-browser: all passed"
