#!/usr/bin/env bash
# A clean feature branch whose only change is committed; origin's default branch is trunk, not main.
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/trunk
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
# The eval workspace holds harness dotfiles; hide untracked files so the tree reads clean.
git config status.showUntrackedFiles no
mkdir -p .claude/ecosystems tools
cat >.claude/ecosystems/bash.yaml <<'EOF'
globs: ["*.sh"]
build-cmd: "bash tools/build.sh <files>"
test-cmd: "bash tools/test.sh"
check-cmd: "bash tools/lint.sh <files>"
fix-cmd: null
code-fix-cmd: null
install-hint: "bash ships with the OS"
EOF
cat >tools/build.sh <<'EOF'
# Checks each script declares strict mode and copies it into build/.
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
# Runs greet.sh and checks its greeting.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=$(bash greet.sh)
[[ "$out" == "hello, trunk" ]]
echo "test: 1 passed"
EOF
cat >tools/lint.sh <<'EOF'
# Fails on trailing whitespace.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $# -gt 0 ]] || set -- greet.sh
if grep -n '[[:space:]]$' "$@"; then exit 1; fi
echo "lint: clean"
EOF
printf 'build/\n' >.gitignore
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' >greet.sh
git add .
git commit -q -m "add greet and tools"

# Bare remote inside the workspace, hidden from status through the local exclude file.
printf '.remote.git/\n' >>.git/info/exclude
git init -q --bare .remote.git
git -C .remote.git symbolic-ref HEAD refs/heads/trunk
git remote add origin "$PWD/.remote.git"
git push -q origin trunk
git remote set-head origin trunk

git switch -q -c feature/greeting
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello, trunk"' >greet.sh
git commit -q -am "greet with the branch name"
