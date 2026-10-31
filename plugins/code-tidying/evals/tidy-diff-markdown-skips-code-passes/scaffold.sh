#!/usr/bin/env bash
# Commits a README on main, adds an uncommitted docs/setup.md whose fenced js block holds code-looking residue, and writes the lines file naming all 11 of its lines.
set -euo pipefail

git init -q
git symbolic-ref HEAD refs/heads/main
printf '%s\n' '# orders-cli' >README.md
git add README.md
git -c user.name=dev -c user.email=dev@example.invalid -c commit.gpgsign=false commit -q -m "add readme"
mkdir -p docs
cat >docs/setup.md <<'EOF'
# Setup

Basically, in order to get started, you will really just need to install the CLI first.

```js
// increment the counter
count++;
console.log("here");
```

Run `orders-cli init` in the project root.
EOF
printf '1\t11\tdocs/setup.md\n' >changed-lines.tsv
