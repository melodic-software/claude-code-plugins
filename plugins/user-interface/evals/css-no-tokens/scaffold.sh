#!/usr/bin/env bash
# Seeds a plain static page with no tokens or design system.
set -euo pipefail

cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Plans</title><link rel="stylesheet" href="styles.css"></head>
<body>
  <header class="site-header">Plans</header>
  <main class="plans">
    <article class="plan-card">Starter</article>
    <article class="plan-card plan-card--popular">Team</article>
  </main>
</body>
</html>
HTML
cat > styles.css <<'CSS'
body { font-family: system-ui, sans-serif; margin: 0; }
.site-header { font-weight: 700; }
CSS
