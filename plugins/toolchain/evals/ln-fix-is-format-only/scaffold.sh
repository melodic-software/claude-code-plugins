#!/usr/bin/env bash
# A repo whose tracked bash.yaml has a format-only fix-cmd and a separate code-fix-cmd, each leaving its own marker.
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
test-cmd: null
check-cmd: "bash tools/lint.sh <files>"
fix-cmd: "bash tools/format.sh <files>"
code-fix-cmd: "bash tools/semantic-fix.sh <files>"
install-hint: "bash ships with the OS"
EOF
cat >tools/lint.sh <<'EOF'
# Fails on trailing whitespace.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $# -gt 0 ]] || set -- app.sh
if grep -n '[[:space:]]$' "$@"; then exit 1; fi
echo "lint: clean"
EOF
cat >tools/format.sh <<'EOF'
# Strips trailing whitespace and records that formatting ran.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
for f in "$@"; do
  sed -i 's/[[:space:]]*$//' "$f"
  grep -qx '# format: applied' "$f" || printf '# format: applied\n' >>"$f"
done
EOF
cat >tools/semantic-fix.sh <<'EOF'
# Renames the deprecated function and records that it ran.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
for f in "$@"; do
  sed -i 's/legacy_greeting/greet/g' "$f"
  printf '# code-fix applied\n' >>"$f"
done
EOF
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'legacy_greeting() { echo "hi"; }' >app.sh
git add .
git commit -q -m "add app and tools"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail  ' 'legacy_greeting() { echo "hello"; }' 'legacy_greeting' >app.sh
