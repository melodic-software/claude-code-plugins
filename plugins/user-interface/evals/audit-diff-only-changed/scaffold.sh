#!/usr/bin/env bash
# A committed repository with two animated stylesheets; only src/menu.css has an uncommitted change.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" .git src index.html
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head><link rel="stylesheet" href="src/menu.css"><link rel="stylesheet" href="src/toast.css"></head>
  <body><div class="menu" role="menu"></div><div class="toast" role="status"></div></body>
</html>
HTML
cat > src/menu.css <<'CSS'
.menu { opacity: 0; transform: scale(0.96); transform-origin: top left; }
@media (prefers-reduced-motion: no-preference) {
  .menu { transition: opacity 180ms cubic-bezier(0.23, 1, 0.32, 1), transform 180ms cubic-bezier(0.23, 1, 0.32, 1); }
}
.menu[data-open] { opacity: 1; transform: none; }
CSS
cat > src/toast.css <<'CSS'
.toast { transform: scale(0); transition: all 700ms ease-in; }
.toast[data-open] { transform: scale(1); }
CSS
git add -A
git commit -q -m "feat: menu and toast"
cat > src/menu.css <<'CSS'
.menu { opacity: 0; transform: scale(0); }
.menu { transition: all 450ms ease-in; }
.menu[data-open] { opacity: 1; transform: scale(1); }
CSS
