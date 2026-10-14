#!/usr/bin/env bash
# A repo whose tracked bash.yaml lints through a tool that is on no PATH, with one changed .sh file.
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/trunk
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
mkdir -p .claude/ecosystems
cat >.claude/ecosystems/bash.yaml <<'EOF'
globs: ["*.sh"]
build-cmd: null
test-cmd: null
check-cmd: "qqfmt-absent --check <files>"
fix-cmd: null
code-fix-cmd: null
install-hint: "ask the platform team for the qqfmt-absent package"
EOF
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' >app.sh
git add .
git commit -q -m "add app"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello"' >app.sh
