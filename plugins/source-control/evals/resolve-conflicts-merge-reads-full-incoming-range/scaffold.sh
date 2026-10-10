#!/usr/bin/env bash
# A merge of ops/tuning into feature stopped on config/retry.yaml. ops/tuning has three commits;
# only the first touched the file, so `git show MERGE_HEAD -- config/retry.yaml` is empty.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p config docs
printf 'retry:\n  max_attempts: 3\n  backoff_seconds: 1\n' > config/retry.yaml
cat > check_config.py <<'PY'
import sys

values = {}
for line in open("config/retry.yaml"):
    line = line.strip()
    if ":" in line and not line.endswith(":"):
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()
ok = set(values) == {"max_attempts", "backoff_seconds"} and all(v.isdigit() for v in values.values())
print("config ok" if ok else "config invalid: %r" % values)
sys.exit(0 if ok else 1)
PY
printf '# ops\n' > docs/ops.md
printf 'lint:\n\t@echo lint\n' > Makefile
git add .
git commit -q -m "chore: retry config"

git checkout -q -b ops/tuning
sed -i 's/max_attempts: 3/max_attempts: 5/' config/retry.yaml
git add config/retry.yaml
git commit -q -m "ops: allow five retry attempts" -m "The payments gateway drops about 1 in 40 calls during its nightly failover; three attempts were not enough to ride it out. Refs OPS-311."
printf '# ops\n\nRetries ride out the nightly failover.\n' > docs/ops.md
git add docs/ops.md
git commit -q -m "docs: note retry behavior"
printf 'lint:\n\t@echo lint --strict\n' > Makefile
git add Makefile
git commit -q -m "chore: strict lint target"

git checkout -q main
git checkout -q -b feature
sed -i 's/backoff_seconds: 1/backoff_seconds: 2/' config/retry.yaml
git add config/retry.yaml
git commit -q -m "perf: double the retry backoff" -m "Cold starts stampeded the cache with retries one second apart. Refs PERF-77."

git merge ops/tuning -q -m "Merge branch ops/tuning into feature" >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
grep -qx config/retry.yaml < <(git diff --name-only --diff-filter=U)
test -z "$(git show --format= MERGE_HEAD -- config/retry.yaml)"
