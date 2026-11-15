#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/comment-tooling-seed.sh"
git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p docs/conventions
printf '%s\n' 'comment_edit_scope: files' >docs/conventions/code-tidying.yaml
cat >tally.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# set the count to zero
count=0
echo "$count"
EOF
cat >untouched.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# set the total to zero
total=0
echo "$total"
EOF
git add docs/conventions/code-tidying.yaml tally.sh untouched.sh
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
git checkout -q -b feature/tally-done
printf '%s\n' 'echo "done"' >>tally.sh
git add tally.sh
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "print done after the count"
