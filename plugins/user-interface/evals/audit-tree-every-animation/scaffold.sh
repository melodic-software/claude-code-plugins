#!/usr/bin/env bash
# An app whose stylesheets in two directories animate with many known defects.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src index.html
mkdir -p src/components src/pages
cat > index.html <<'HTML'
<!doctype html>
<html lang="en"><head><link rel="stylesheet" href="src/pages/home.css"></head><body></body></html>
HTML
cat > src/components/cards.css <<'CSS'
.card { transition: all 600ms ease-in; }
.card:hover { transform: scale(1.08); box-shadow: 0 20px 40px rgb(0 0 0 / 0.3); }
.card__badge { animation: pulse 1s infinite; }
@keyframes pulse { from { transform: scale(1); } to { transform: scale(1.2); } }
CSS
cat > src/components/sidebar.css <<'CSS'
.sidebar { width: 0; transition: width 500ms ease-in-out; }
.sidebar[data-open] { width: 280px; }
.sidebar__item:hover { padding-left: 24px; transition: padding-left 300ms; }
CSS
cat > src/pages/home.css <<'CSS'
.hero { animation: hero-in 1200ms ease-in both; }
@keyframes hero-in { from { opacity: 0; transform: scale(0); } to { opacity: 1; transform: none; } }
.section { opacity: 0; transform: translateY(80px); transition: all 900ms; }
.section.is-visible { opacity: 1; transform: none; }
.modal { transform: scale(0); transition: transform 700ms ease-in; }
.modal[open] { transform: scale(1); }
CSS
