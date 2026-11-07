#!/usr/bin/env bash
# A small app with launch defects: a leaked session log, an unlabeled icon button and a defective modal animation.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src index.html
mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="src/styles.css"><script src="src/app.js" defer></script></head>
  <body>
    <header><button class="share"><svg width="16" height="16" aria-hidden="true"></svg></button></header>
    <dialog class="modal"><h2>Share</h2><button class="close">Close</button></dialog>
  </body>
</html>
HTML
cat > src/styles.css <<'CSS'
.modal { transform: scale(0); transition: all 600ms ease-in; }
.modal[open] { transform: scale(1); }
.share:hover { transform: scale(1.1); }
.close:focus { outline: none; }
CSS
cat > src/app.js <<'JS'
const session = { user: "ada@example.invalid", token: "placeholder" };
console.log("session", session);
document.querySelector(".share").addEventListener("click", () => document.querySelector(".modal").showModal());
document.querySelector(".close").addEventListener("click", () => document.querySelector(".modal").close());
JS
