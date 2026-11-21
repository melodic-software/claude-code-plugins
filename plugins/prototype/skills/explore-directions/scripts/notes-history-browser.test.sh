#!/usr/bin/env bash
# test-scope: plugins/prototype/notes-bridge/* plugins/prototype/skills/explore-directions/assets/variant-switcher.html
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
# shellcheck source=../../../lib/browser-test-helpers.sh
source "$here/../../../lib/browser-test-helpers.sh"
browser_setup ed-notes-history edh playwright-cli python3 curl

marker='<!-- The bundled assets/variant-switcher.html is inlined whole here; elided from this fixture. -->'
while IFS= read -r line; do
  if [[ "$line" == "$marker" ]]; then cat "$skill/assets/variant-switcher.html"; else printf '%s\n' "$line"; fi
done <"$skill/evals/fixtures/shipments-mockup.html" >"$d/explore-directions.html"

browser_serve

pw open >/dev/null 2>&1
sed "s/__PORT__/$port/" "$here/notes-history-browser-take.js" >"$tmp/take.js"
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

if ((fails)); then
  echo "notes-history-browser: $fails failed"
  exit 1
fi
echo "notes-history-browser: all passed"
