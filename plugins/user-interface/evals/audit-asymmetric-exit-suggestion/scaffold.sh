#!/usr/bin/env bash
# Seeds a plain HTML and CSS app whose dropdown menu exits faster than it enters.
set -euo pipefail

mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head><link rel="stylesheet" href="src/menu.css"></head>
  <body>
    <button aria-expanded="false" aria-controls="menu">Options</button>
    <ul id="menu" class="menu" data-open="false"><li>Rename</li><li>Duplicate</li></ul>
  </body>
</html>
HTML
cat > src/menu.css <<'CSS'
.menu {
  transform-origin: top left;
  opacity: 0;
  transform: scale(0.96);
  transition:
    opacity 190ms cubic-bezier(0.23, 1, 0.32, 1),
    transform 190ms cubic-bezier(0.23, 1, 0.32, 1);
}
.menu[data-open="true"] {
  opacity: 1;
  transform: scale(1);
  transition-duration: 200ms;
}
@media (prefers-reduced-motion: reduce) {
  .menu { transition-property: opacity; }
}
CSS
