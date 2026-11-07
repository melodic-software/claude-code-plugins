#!/usr/bin/env bash
# A committed repository whose src/drawer.css has an uncommitted change with several animation defects.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" .git src index.html
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en"><head><link rel="stylesheet" href="src/drawer.css"></head><body><aside class="drawer"></aside></body></html>
HTML
cat > src/drawer.css <<'CSS'
.drawer { position: fixed; inset-block: 0; inset-inline-end: 0; inline-size: 360px; transform: translateX(100%); }
@media (prefers-reduced-motion: no-preference) {
  .drawer { transition: transform 300ms cubic-bezier(0.32, 0.72, 0, 1); }
}
.drawer[data-open] { transform: none; }
CSS
git add -A
git commit -q -m "feat: drawer"
cat > src/drawer.css <<'CSS'
.drawer { position: fixed; inset-block: 0; inset-inline-end: 0; inline-size: 360px; transform: scale(0); }
.drawer { transition: all 450ms ease-in; }
.drawer[data-open] { transform: scale(1); }
CSS
