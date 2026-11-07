#!/usr/bin/env bash
# An app with its own motion tokens and an unanimated dropdown.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src index.html
mkdir -p src/components src/styles
cat > index.html <<'HTML'
<!doctype html>
<html lang="en"><head><link rel="stylesheet" href="src/styles/motion.css"><link rel="stylesheet" href="src/components/dropdown.css"></head>
<body><div class="dropdown"><button class="dropdown-trigger">Sort</button><ul class="dropdown-menu" role="menu"><li role="menuitem">Newest</li></ul></div></body></html>
HTML
cat > src/styles/motion.css <<'CSS'
:root {
  --motion-ease-enter: cubic-bezier(0.2, 0, 0, 1);
  --motion-ease-exit: cubic-bezier(0.3, 0, 1, 1);
  --motion-fast: 140ms;
  --motion-medium: 220ms;
}
CSS
cat > src/components/dropdown.css <<'CSS'
.dropdown { position: relative; }
.dropdown-menu { position: absolute; inset-block-start: calc(100% + 4px); inset-inline-start: 0; display: none; }
.dropdown[data-open] .dropdown-menu { display: block; }
CSS
