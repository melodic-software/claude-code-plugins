#!/usr/bin/env bash
# Seeds a repository with a small git-hooks system: a dispatcher, two hooks and a config listing them.
set -euo pipefail

git init -q .
mkdir -p hooks/pre-commit.d
cat >AGENTS.md <<'EOF'
# shop-api

Git hooks live in `hooks/`. `hooks/run-hook.sh <event>` runs every executable in
`hooks/<event>.d/` in name order and stops at the first non-zero exit. `hooks/hooks.conf` lists the
events that are enabled. Install with `git config core.hooksPath hooks`.
EOF
cat >hooks/hooks.conf <<'EOF'
pre-commit
EOF
cat >hooks/run-hook.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
event="$1"
grep -qx "$event" "$(dirname "$0")/hooks.conf" || exit 0
for step in "$(dirname "$0")/$event.d"/*; do
  [ -x "$step" ] || continue
  "$step" || { echo "hook $event: $(basename "$step") failed" >&2; exit 1; }
done
EOF
cat >hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exec "$(dirname "$0")/run-hook.sh" pre-commit
EOF
cat >hooks/pre-commit.d/10-no-debug-prints.sh <<'EOF'
#!/usr/bin/env bash
! git diff --cached -U0 | grep -nE '^\+.*console\.log\('
EOF
cat >hooks/pre-commit.d/20-json-valid.sh <<'EOF'
#!/usr/bin/env bash
git diff --cached --name-only -- '*.json' | while read -r f; do node -e "JSON.parse(require('fs').readFileSync('$f'))"; done
EOF
chmod +x hooks/run-hook.sh hooks/pre-commit hooks/pre-commit.d/*.sh
