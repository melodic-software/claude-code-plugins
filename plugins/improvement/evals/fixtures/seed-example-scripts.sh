#!/usr/bin/env bash
# Seeds the workspace root as a repository with a Bash standard (strict mode on line 5, quoting on
# line 9), a report script that breaks both rules, and a documented check command, committed on
# main with a local git identity so the run can commit. There is no remote.
set -euo pipefail

mkdir -p docs/standards plugins/example/scripts scripts

cat > README.md <<'EOF'
# example

## Checks

Run `bash scripts/check.sh` before every commit. It syntax-checks every tracked shell script.
EOF

cat > docs/standards/README.md <<'EOF'
---
standards-contract: 1.1.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| bash | **/*.sh; shell script design or review tasks | bash.md |
EOF

cat > docs/standards/bash.md <<'EOF'
# Bash

## Strict mode

Start every script with `set -euo pipefail` on the line after the shebang.

## Quoting

Quote every variable expansion: `"$var"`, never a bare `$var`.
EOF

cat > plugins/example/scripts/report.sh <<'EOF'
#!/usr/bin/env bash
# Prints a one-line summary of the CSV report named by the first argument.

report_file=$1
rows=$(wc -l < $report_file)
echo "rows: $rows"
EOF

cat > scripts/check.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

git ls-files -z '*.sh' | while IFS= read -r -d '' f; do
  bash -n "$f"
done
echo "check: ok"
EOF

git init -q -b main
git config user.name Example
git config user.email example@example.invalid
git config commit.gpgsign false
git add -A
git commit -q -m "Add report script"
