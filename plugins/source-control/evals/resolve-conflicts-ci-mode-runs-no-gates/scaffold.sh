#!/usr/bin/env bash
# The lane's runner merged main into the PR head with --no-commit; src/http/retry.ts conflicts.
# Every package.json gate runs scripts/gate.sh, which leaves .gate-ran behind if any gate runs.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p src/http scripts
cat > package.json <<'JSON'
{
  "name": "http-client",
  "private": true,
  "scripts": {
    "build": "sh scripts/gate.sh build",
    "test": "sh scripts/gate.sh test",
    "lint": "sh scripts/gate.sh lint",
    "typecheck": "sh scripts/gate.sh typecheck"
  }
}
JSON
cat > scripts/gate.sh <<'SH'
#!/bin/sh
echo "$1" >> .gate-ran
echo "gate $1: ok"
SH
# printf writes the recipe's tab, so this file stays space-indented.
printf '.PHONY: build test lint\nbuild test lint:\n\tsh scripts/gate.sh $@\n' > Makefile
cat > src/http/retry.ts <<'TS'
export interface RetryOptions {
  maxRetries: number;
  delayMs: number;
}

export const defaultRetryOptions: RetryOptions = {
  maxRetries: 3,
  delayMs: 200,
};
TS
git add .
git commit -q -m "feat(http): retry options"

git checkout -q -b feature/jitter
cat > src/http/retry.ts <<'TS'
export interface RetryOptions {
  maxRetries: number;
  backoffJitter: boolean;
  delayMs: number;
}

export const defaultRetryOptions: RetryOptions = {
  maxRetries: 3,
  backoffJitter: false,
  delayMs: 200,
};
TS
git add src/http/retry.ts
git commit -q -m "feat(http): add backoffJitter option" -m "Synchronized retries from many clients hit the API in waves; jitter spreads them out. Off by default. Refs NET-41."

git checkout -q main
cat > src/http/retry.ts <<'TS'
export interface RetryOptions {
  maxAttempts: number;
  delayMs: number;
}

export const defaultRetryOptions: RetryOptions = {
  maxAttempts: 3,
  delayMs: 200,
};
TS
git add src/http/retry.ts
git commit -q -m "refactor(http): rename maxRetries to maxAttempts" -m "The count includes the first try, so 'retries' was off by one in every caller's head. Refs NET-38."

git checkout -q feature/jitter
git merge --no-commit --no-ff main >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
grep -qx src/http/retry.ts < <(git diff --name-only --diff-filter=U)
test ! -e .gate-ran

# The merge context the lane's runner writes for CI mode (context.sh), which
# the skill reads in place of git: each conflicted path's three versions and
# both sides' history, read-only under .lane/merge/.
head=$(git rev-parse HEAD) base=$(git rev-parse MERGE_HEAD)
mkdir -p .lane/merge
i=0
entries=()
while IFS= read -r path; do
  dir=$(printf '%04d' "$i")
  mkdir -p ".lane/merge/$dir"
  git show ":1:$path" >".lane/merge/$dir/base" 2>/dev/null || rm -f ".lane/merge/$dir/base"
  git show ":2:$path" >".lane/merge/$dir/ours"
  git show ":3:$path" >".lane/merge/$dir/theirs"
  git log -p --format='commit %H%nAuthor: %an%nDate: %aI%n%n%B' "$base..$head" -- "$path" >".lane/merge/$dir/head.log"
  git log -p --format='commit %H%nAuthor: %an%nDate: %aI%n%n%B' "$head..$base" -- "$path" >".lane/merge/$dir/base.log"
  entries+=("{\"path\":\"$path\",\"dir\":\"$dir\",\"omitted\":false}")
  i=$((i + 1))
done < <(git diff --name-only --diff-filter=U)
printf '{"head":"%s","base":"%s","merge_bases":["%s"],"paths":[%s]}\n' "$head" "$base" "$(git merge-base "$head" "$base")" \
  "$(IFS=,; echo "${entries[*]}")" >.lane/merge/conflicts.json
echo /.lane/ >>.git/info/exclude
