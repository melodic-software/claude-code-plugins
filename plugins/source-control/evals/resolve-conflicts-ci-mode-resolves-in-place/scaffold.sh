#!/usr/bin/env bash
# The lane's runner merged main into the PR head with --no-commit; src/http/retry.ts and
# docs/retry.md conflict. Graders read the final .git/index directly: git hooks do not run in
# the eval sandbox, so nothing here may depend on one.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p src/http docs
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
cat > docs/retry.md <<'MD'
# Retry

Requests retry on failure.

## Options

- `maxRetries`: how many times a request is tried.
- `delayMs`: the wait between tries.
MD
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
cat > docs/retry.md <<'MD'
# Retry

Requests retry on failure.

## Options

- `maxRetries`: how many times a request is tried.
- `backoffJitter`: spread retries randomly across the delay window.
- `delayMs`: the wait between tries.

## Jitter

With `backoffJitter` on, each wait is a random time up to `delayMs`, so clients that failed
together do not retry together.
MD
git add src/http/retry.ts docs/retry.md
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
cat > docs/retry.md <<'MD'
# Retry

Requests retry on transient failures: 5xx responses and timeouts.

## Options

- `maxAttempts`: how many times a request is tried, the first try included.
- `delayMs`: the wait between tries.
MD
git add src/http/retry.ts docs/retry.md
git commit -q -m "refactor(http): rename maxRetries to maxAttempts" -m "The count includes the first try, so 'retries' was off by one in every caller's head. The docs now say which failures retry. Refs NET-38."

git checkout -q feature/jitter
git merge --no-commit --no-ff main >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
test "$(git diff --name-only --diff-filter=U | sort | tr '\n' ' ')" = "docs/retry.md src/http/retry.ts "

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
