#!/usr/bin/env bash
# A sidebar that opens by animating width and left.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src index.html
mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head><link rel="stylesheet" href="src/sidebar.css"><script src="src/sidebar.js" defer></script></head>
  <body><button class="menu-button" aria-expanded="false">Menu</button><nav class="sidebar"><a href="/">Home</a></nav></body>
</html>
HTML
cat > src/sidebar.css <<'CSS'
.sidebar {
  position: fixed;
  inset-block: 0;
  left: -280px;
  width: 0;
  overflow: hidden;
  box-shadow: 0 0 40px rgb(0 0 0 / 0.4);
  transition: width 300ms cubic-bezier(0.32, 0.72, 0, 1), left 300ms cubic-bezier(0.32, 0.72, 0, 1);
}
.sidebar[data-open] { left: 0; width: 280px; }
CSS
cat > src/sidebar.js <<'JS'
const button = document.querySelector(".menu-button");
const sidebar = document.querySelector(".sidebar");
button.addEventListener("click", () => {
  const open = sidebar.toggleAttribute("data-open");
  button.setAttribute("aria-expanded", String(open));
});
JS
