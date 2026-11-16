#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p scripts measurements src
cat >hooks.yml <<'EOF'
# Hook manager config: which checks run in which git hook stage.
pre-commit:
  commands:
    format-check: { run: scripts/run-checks.sh format }
    shell-lint: { run: scripts/run-checks.sh lint }
pre-push:
  commands:
    type-check: { run: scripts/run-checks.sh types }
    unit-tests: { run: scripts/run-checks.sh tests }
EOF

cat >scripts/run-checks.sh <<'EOF'
#!/usr/bin/env bash
# Runs the named check over every tracked source file, four shards in parallel.
check="$1"
for shard in 0 1 2 3; do
  "scripts/check-$check.sh" "$shard" &
done
wait
EOF
chmod +x scripts/run-checks.sh

cat >measurements/hook-timings.txt <<'EOF'
Per-check timings, 10 runs each on a typical 12-file change, seconds.

| Check | Stage | p50 | p90 | Files inspected |
|---|---|---|---|---|
| format-check | pre-commit | 0.4 | 0.6 | 12 |
| shell-lint | pre-commit | 7.8 | 9.1 | 1840 (every tracked file) |
| type-check | pre-push | 14.2 | 15.0 | whole project |
| unit-tests | pre-push | 52.0 | 61.5 | all 31 suites |

Tracked source files by release: 1.0 = 610, 2.0 = 1120, 3.0 = 1840.
EOF

for i in $(seq 1 20); do printf 'echo %d\n' "$i" >"src/f$i.sh"; done
printf '.work/\n' >.gitignore
git add .
git commit -q -m "hooks, check runner and per-check timings"
