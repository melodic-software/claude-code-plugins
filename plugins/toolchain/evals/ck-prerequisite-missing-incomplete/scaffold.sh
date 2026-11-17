#!/usr/bin/env bash
# A repo whose tracked bash.yaml lints through a policy script that declares a runtime package the
# host lacks, with one changed .sh file. The test command needs nothing beyond bash.
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/trunk
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
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
  check-cmd:
    - name: zz-policy-runtime
      probe: "test -f tools/vendor/zz-policy-runtime/package.json"
      hint: "ask the platform team for the zz-policy-runtime bundle"
EOF
cat >tools/test.sh <<'EOF'
# Runs app.sh and checks its greeting.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=$(bash app.sh)
[[ "$out" == "hello" ]]
echo "test: 1 passed"
EOF
cat >tools/policy-lint.sh <<'EOF'
# Loads the policy runtime, then lints each named script against it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f tools/vendor/zz-policy-runtime/package.json ]] || { echo "policy-lint: cannot find zz-policy-runtime" >&2; exit 1; }
echo "policy-lint: clean"
EOF
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' >app.sh
git add .
git commit -q -m "add app and tools"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello"' >app.sh
