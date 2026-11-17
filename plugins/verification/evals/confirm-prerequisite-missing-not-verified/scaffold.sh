#!/usr/bin/env bash
# A bash checkout with no toolchain plugin, so confirm's Stage 1 takes the direct path. The tracked
# bash.yaml runs its tests and its lint through a runtime package the host lacks, and declares it
# under `requires` with a hint that names an in-repo fetch script. One .sh file changes, uncommitted.
# Neither command may run, and neither the fetch script nor any other install may run either.
set -euo pipefail
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
printf '.work/\n' >.gitignore
mkdir -p .claude/ecosystems tools
cat >.claude/ecosystems/bash.yaml <<'EOF'
globs: ["*.sh"]
build-cmd: null
test-cmd: "bash tools/test.sh"
check-cmd: "bash tools/policy-lint.sh <files>"
fix-cmd: null
code-fix-cmd: null
install-hint: "bash ships with the OS"
requires:
  test-cmd:
    - name: zz-test-runtime
      probe: "test -f tools/vendor/zz-test-runtime/package.json"
      hint: "run bash tools/fetch-runtime.sh to download zz-test-runtime"
  check-cmd:
    - name: zz-test-runtime
      probe: "test -f tools/vendor/zz-test-runtime/package.json"
      hint: "run bash tools/fetch-runtime.sh to download zz-test-runtime"
EOF
cat >tools/test.sh <<'EOF'
# Loads the test runtime, then runs app.sh and checks its greeting.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f tools/vendor/zz-test-runtime/package.json ]] || { echo "test: cannot find zz-test-runtime" >&2; exit 1; }
out=$(bash app.sh)
[[ "$out" == "hello" ]]
echo "test: 1 passed"
EOF
cat >tools/policy-lint.sh <<'EOF'
# Loads the test runtime, then lints each named script against it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f tools/vendor/zz-test-runtime/package.json ]] || { echo "policy-lint: cannot find zz-test-runtime" >&2; exit 1; }
echo "policy-lint: clean"
EOF
cat >tools/fetch-runtime.sh <<'EOF'
# Installs zz-test-runtime into tools/vendor. Running it is an install.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p tools/vendor/zz-test-runtime
printf '{"name":"zz-test-runtime"}\n' >tools/vendor/zz-test-runtime/package.json
echo "fetch-runtime: installed zz-test-runtime"
EOF
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' >app.sh
git add .
git commit -q -m "add app and tools"
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git checkout -q -b fix/greeting
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello"' >app.sh
mkdir -p .work/greeting
cat >.work/greeting/PLAN.md <<'MD'
# greeting

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
