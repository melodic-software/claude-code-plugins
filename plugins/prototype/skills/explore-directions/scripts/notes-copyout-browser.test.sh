#!/usr/bin/env bash
# test-scope: plugins/prototype/notes-bridge/* plugins/prototype/skills/explore-directions/assets/variant-switcher.html plugins/prototype/lib/browser-test-helpers.sh plugins/prototype/skills/explore-directions/scripts/notes-copyout-browser-take.js plugins/prototype/.claude-plugin/plugin.json
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
# shellcheck source=../../../lib/browser-test-helpers.sh
source "$here/../../../lib/browser-test-helpers.sh"
browser_setup ed-notes-copyout edo playwright-cli node python3 curl

cat >"$d/explore-directions.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'">
<title>/shipments variants</title>
<style>
  body { margin: 0; font: 16px system-ui, sans-serif; background: #fff; }
  .bar { display: flex; position: fixed; inset-block-start: 8px; inset-inline-start: 8px; }
  main { padding-block-start: 60px; }
</style>
</head>
<body>
<div class="bar" data-harness-chrome>
  <button type="button" data-data-control="seed:10">Seed 10</button>
  <button type="button" data-data-control="clear">Clear</button>
</div>
<main>
  <section data-variant="A" data-variant-label="Ledger">
    <h2 data-testid="shipments-title">Parcels</h2>
    <ul class="rows"></ul>
  </section>
  <section data-variant="B" data-variant-label="Cards"><p data-testid="shipments-list">Cards</p></section>
  <p><button type="button" id="copy-out">Copy chosen design</button></p>
  <pre id="copied"></pre>
</main>
<script>
  let count = 3;
  function render() {
    document.querySelector('[data-variant="A"] .rows').replaceChildren(...Array.from({ length: count }, (_, i) => {
      const li = document.createElement("li");
      li.dataset.testid = "shipments-row";
      li.textContent = `PT-${1000 + i}`;
      return li;
    }));
  }
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-data-control]");
    if (!b) return;
    count = b.dataset.dataControl === "clear" ? 0 : count + 10;
    render();
  });
  window.uiFeedbackCopyOut = () => {
    const variants = [...document.querySelectorAll("[data-variant]")];
    const shown = variants.find((v) => !v.hidden);
    const ids = (v) => [...new Set([...v.querySelectorAll("[data-testid]")].map((x) => x.dataset.testid))].join(", ");
    const lines = [`direction: ${shown.dataset.variant} ${shown.dataset.variantLabel}`, `test-ids: ${variants.map((v) => `${v.dataset.variant}: ${ids(v)}`).join("; ")}`];
    if (window.__markup) lines.push('notes: <img src=x onerror="window.__xss=1">');
    return lines.join("\n");
  };
  document.getElementById("copy-out").addEventListener("click", () => { document.getElementById("copied").textContent = window.uiFeedbackCopyOut(); });
  render();
</script>
HTML
cat "$skill/assets/variant-switcher.html" >>"$d/explore-directions.html"
printf '%s\n' '</body>' '</html>' >>"$d/explore-directions.html"

browser_serve

pw open >/dev/null 2>&1
python3 -c '
import sys
src, dst, port, page = sys.argv[1:]
text = open(src, encoding="utf-8").read().replace("__PORT__", port).replace("__FILE__", "file://" + page)
open(dst, "w", encoding="utf-8", newline="\n").write(text)
' "$here/notes-copyout-browser-take.js" "$tmp/take.js" "$port" "$d/explore-directions.html"
n=0
while IFS= read -r line; do
  n=$((n + 1))
  case "$line" in
    PASS\ *) ok "take: ${line#PASS }" ;;
    *) bad "take: $line" ;;
  esac
done < <(code "$tmp/take.js" | result | tr -d '\r' | grep -E '^(PASS|FAIL|ERROR) ')
((n > 0)) || bad "take: no results"

if ((fails)); then
  echo "notes-copyout-browser: $fails failed"
  exit 1
fi
echo "notes-copyout-browser: all passed"
