#!/usr/bin/env bash
# test-scope: plugins/prototype/notes-bridge/* plugins/prototype/skills/explore-directions/assets/variant-switcher.html plugins/prototype/skills/explore-directions/evals/fixtures/shipments-mockup.html plugins/prototype/lib/browser-test-helpers.sh plugins/prototype/skills/explore-directions/scripts/notes-edit-browser-take.js plugins/prototype/.claude-plugin/plugin.json
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
# shellcheck source=../../../lib/browser-test-helpers.sh
source "$here/../../../lib/browser-test-helpers.sh"
browser_setup ed-notes-edit ede playwright-cli python3 curl

marker='<!-- The bundled assets/variant-switcher.html is inlined whole here; elided from this fixture. -->'
while IFS= read -r line; do
  if [[ "$line" == "$marker" ]]; then cat "$skill/assets/variant-switcher.html"; else printf '%s\n' "$line"; fi
done <"$skill/evals/fixtures/shipments-mockup.html" >"$d/explore-directions.html"

browser_serve

pw open >/dev/null 2>&1
sed "s/__PORT__/$port/" "$here/notes-edit-browser-take.js" >"$tmp/take.js"
out=$(code "$tmp/take.js")
n=0
while IFS= read -r line; do
  n=$((n + 1))
  case "$line" in
    PASS\ *) ok "take: ${line#PASS }" ;;
    *) bad "take: $line" ;;
  esac
done < <(printf '%s\n' "$out" | result | tr -d '\r' | grep -E '^(PASS|FAIL|ERROR) ')
((n > 0)) || bad "take: no results ($(printf '%s' "$out" | head -c 1500))"

log=$(cat "$d/actions.json")
check "the log holds both notes under seqs 1 and 2, note 1 with its edited text" \
  'e = r["events"]; assert [(x["seq"], x["text"]) for x in e[:2]] == [(1, "Bolder and larger parcel ids."), (2, "Dates first.")], e' "$log"
check "the edit and the withdraw are logged as events naming their notes" \
  'e = r["events"][2:]; assert [(x["seq"], x.get("edit"), x.get("withdraw")) for x in e] == [(3, 1, None), (4, None, 2)], e' "$log"
check "status lists note 1 and its edit, and the withdraw, but not the withdrawn note" \
  'assert [x["seq"] for x in r["events"]] == [1, 3, 4], r' "$(bash "$bridge/notes-bridge.sh" --dir "$d" status)"

if ((fails)); then
  echo "notes-edit-browser: $fails failed"
  exit 1
fi
echo "notes-edit-browser: all passed"
