#!/usr/bin/env bash
# A small repo whose CLAUDE.md carries a line the model follows unaided ("Read a file before you
# edit it."), next to one project-specific line it could not know. docs-hygiene is not loaded.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src
cat >src/greet.ts <<'EOF'
export const greet = (name: string) => `Hello, ${name}!`;
EOF
cat >CLAUDE.md <<'EOF'
# greeter

- Read a file before you edit it.
- Release notes go in docs/releases/<version>.md, never in the README.
EOF
git add .
git commit -q -m "feat: greeter"
