#!/usr/bin/env bash
# Seeds a git repository with an origin remote (never fetched) and one committed slugify change.
set -euo pipefail

git init -q .
git remote add origin https://github.com/example-org/widget-shop.git
mkdir -p src
cat >src/slugify.js <<'EOF'
function slugify(title) {
  return title.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-");
}
module.exports = { slugify };
EOF
git add src/slugify.js
git -c user.name=Eval -c user.email=eval@example.com commit -qm "feat: add slugify"
cat >src/slugify.js <<'EOF'
function slugify(title) {
  return title
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}
module.exports = { slugify };
EOF
git -c user.name=Eval -c user.email=eval@example.com commit -qam "fix(slugify): strip accents and edge hyphens"
