#!/usr/bin/env bash
# A repo whose tracked bash.yaml passes build, test and lint but declares a gate that fails.
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/trunk
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
mkdir -p .claude/ecosystems tools
cat >.claude/ecosystems/bash.yaml <<'EOF'
globs: ["*.sh"]
build-cmd: "bash tools/build.sh <files>"
test-cmd: "bash tools/test.sh"
check-cmd: "bash tools/lint.sh <files>"
fix-cmd: null
code-fix-cmd: null
install-hint: "bash ships with the OS"
gates:
  - name: fixture-drift
    cmd: "bash tools/fixture-drift.sh"
    remediation: "run tools/regen-fixtures.sh and commit the regenerated fixtures"
    trigger-globs: ["*.sh"]
EOF
cat >tools/build.sh <<'EOF'
# Builds each script into build/ and checks it declares strict mode.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
for f in "$@"; do
  grep -q '^set -euo pipefail$' "$f"
  cp "$f" "build/$(basename "$f")"
done
echo "build: ${#} script(s) built"
EOF
cat >tools/test.sh <<'EOF'
# Runs app.sh and checks its greeting.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=$(bash app.sh)
[[ "$out" == "hello" ]]
echo "test: 1 passed"
EOF
cat >tools/lint.sh <<'EOF'
# Fails on trailing whitespace.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $# -gt 0 ]] || set -- app.sh
if grep -n '[[:space:]]$' "$@"; then exit 1; fi
echo "lint: clean"
EOF
cat >tools/fixture-drift.sh <<'EOF'
# Fails: the recorded fixture no longer matches the app's output.
echo "fixture-drift: fixtures/greeting.txt says 'hi', app.sh prints 'hello'" >&2
exit 1
EOF
printf 'build/\n' >.gitignore
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' >app.sh
git add .
git commit -q -m "add app and tools"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello"' >app.sh
