#!/usr/bin/env bash
# A small app with no animation: a command palette, a save button, a data table and a settings modal.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src index.html
mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head><link rel="stylesheet" href="src/app.css"><script src="src/app.js" defer></script></head>
  <body>
    <header><button class="gear" aria-label="Settings">&#9881;</button></header>
    <main>
      <table class="ledger"><thead><tr><th>Date</th><th>Payee</th><th>Amount</th></tr></thead><tbody></tbody></table>
      <button class="save">Save</button><span class="save-status" role="status"></span>
    </main>
    <dialog class="settings"><h2>Settings</h2><button class="close">Close</button></dialog>
    <div class="palette" role="dialog" aria-label="Command palette" hidden><input aria-label="Command"></div>
  </body>
</html>
HTML
cat > src/app.css <<'CSS'
.ledger { inline-size: 100%; border-collapse: collapse; }
.ledger td { padding-block: 4px; }
.save-status { margin-inline-start: 8px; }
.palette { position: fixed; inset-block-start: 20vh; inset-inline: 0; margin-inline: auto; inline-size: 560px; }
.settings { inline-size: 420px; }
CSS
cat > src/app.js <<'JS'
const palette = document.querySelector(".palette");
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "k") { e.preventDefault(); palette.hidden = !palette.hidden; }
});
document.querySelector(".gear").addEventListener("click", () => document.querySelector(".settings").showModal());
document.querySelector(".save").addEventListener("click", () => { document.querySelector(".save-status").textContent = "Saved"; });
JS
