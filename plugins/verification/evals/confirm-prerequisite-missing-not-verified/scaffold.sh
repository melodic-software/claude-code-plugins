#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false

printf '.work/\n' > .gitignore
mkdir -p .claude/ecosystems tools
cat > .claude/ecosystems/bash.yaml <<'EOF'
globs: ["*.sh"]
build-cmd: null
test-cmd: "bash tools/test.sh"
check-cmd: "bash tools/policy-lint.sh <files>"
fix-cmd: null
code-fix-cmd: null
install-hint: "bash ships with the OS"
requires:
  check-cmd:
    - name: zz-policy-runtime
      probe: "test -f tools/vendor/zz-policy-runtime/package.json"
      hint: "ask the platform team for the zz-policy-runtime bundle"
EOF
cat > tools/test.sh <<'EOF'
# Runs app.sh and checks its greeting.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=$(bash app.sh)
[[ "$out" == "hello" ]]
echo "test: 1 passed"
EOF
cat > tools/policy-lint.sh <<'EOF'
# Loads the policy runtime, then lints each named script against it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f tools/vendor/zz-policy-runtime/package.json ]] || { echo "policy-lint: cannot find zz-policy-runtime" >&2; exit 1; }
echo "policy-lint: clean"
EOF
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' > app.sh
git add .
git commit -q -m "chore: add app and tools"

mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git checkout -q -b feat/hello-greeting

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello"' > app.sh

mkdir -p .work/hello-greeting
cat > .work/hello-greeting/PLAN.md <<'MD'
# hello greeting

Approval: approved by the maintainer in the planning session

## Brief

Goal: `app.sh` greets with `hello` instead of `hi`.

### Acceptance criteria

- AC1: `bash app.sh` prints `hello`.

## Plan

### Phase 1: greeting [DONE]

- Change the echo in `app.sh`.
- **Sanity Check:** `bash tools/test.sh` exits 0.
MD
