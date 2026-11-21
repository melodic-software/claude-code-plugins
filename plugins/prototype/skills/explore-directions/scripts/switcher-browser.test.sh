#!/usr/bin/env bash
# test-scope: plugins/prototype/skills/explore-directions/assets/variant-switcher.html
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
# shellcheck source=../../../lib/browser-test-helpers.sh
source "$here/../../../lib/browser-test-helpers.sh"
browser_setup ed-switcher eds playwright-cli python3 curl

page="$d/switcher.html"
{
  cat <<'HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Switcher</title>
<style>@keyframes rise { from { opacity: 0; } to { opacity: 1; } } .card { animation: rise 200ms; }</style>
</head>
<body>
<section data-variant="A" data-variant-label="Editorial column">
  <div data-screen-state="full" data-screen-state-label="Full"><p class="card" data-content-set="demo">Demo</p><p data-content-set="worst">Worst</p></div>
  <div data-screen-state="empty" data-screen-state-label="Empty"><p>Nothing yet</p></div>
</section>
<section data-variant="B" data-variant-label="Split board with long label"><p class="card">B</p></section>
<section data-variant="C" data-variant-label="Dense operations grid"><p class="card">C</p></section>
<section data-variant="D" data-variant-label="Timeline with side panel"><p class="card">D</p></section>
HTML
  cat "$skill/assets/variant-switcher.html"
  printf '</body>\n</html>\n'
} >"$page"

if command -v cygpath >/dev/null 2>&1; then url="file:///$(cygpath -m "$page")"; else url="file://$page"; fi
sed "s|__FILE__|$url|" "$here/switcher-browser.js" >"$tmp/switcher.js"

pw open >/dev/null 2>&1
n=0
while IFS= read -r line; do
  n=$((n + 1))
  case "$line" in
    PASS\ *) ok "${line#PASS }" ;;
    *) bad "${line#FAIL }" ;;
  esac
done < <(code "$tmp/switcher.js" | result | tr -d '\r' | grep -E '^(PASS|FAIL|ERROR) ')
((n > 0)) || bad "the page script returned no results"

if ((fails)); then
  echo "switcher-browser: $fails failed"
  exit 1
fi
echo "switcher-browser: all passed"
