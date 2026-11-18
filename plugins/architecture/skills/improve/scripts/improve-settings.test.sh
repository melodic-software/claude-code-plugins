#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SUT="$SCRIPT_DIR/improve-settings.mjs"
command -v node >/dev/null 2>&1 || { echo "node is required" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0
check() {
  local name="$1" expected="$2" projection="$3" repo="$4"
  shift 4
  local actual
  actual="$(node "$SUT" --repo "$repo" "$@" | node -e '
    let text = "";
    process.stdin.on("data", (chunk) => { text += chunk; });
    process.stdin.on("end", () => {
      const r = JSON.parse(text);
      process.stdout.write(JSON.stringify(eval(process.argv[1])));
    });' "$projection")" || actual="(the script failed)"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok: $name"
  else
    echo "FAIL: $name" >&2
    printf '  expected: %s\n  actual:   %s\n' "$expected" "$actual" >&2
    failed=1
  fi
}

repo_with() {
  local dir="$work/$1"
  mkdir -p "$dir/docs/conventions"
  printf '%s\n' "$dir"
}

empty="$(repo_with empty)"
check "with no file, the threshold admits every band" '"Speculative"' 'r.values.unattended_min_badge' "$empty"
check "with no file, the scan reads the newest 100 commits" '100' 'r.values.history_commits' "$empty"
check "with no file, bot authors are left out" '["[bot]"]' 'r.values.exclude_authors' "$empty"
check "with no file, every value is the default's" '"defaults"' 'r.source.unattended_min_badge' "$empty"
check "with no file, nothing is reported" '[]' 'r.errors' "$empty"

team="$(repo_with team)"
cat >"$team/docs/conventions/architecture.yaml" <<'YAML'
improve:
  unattended_min_badge: Strong
  history_commits: 250
  exclude_authors:
    - "release-bot"
YAML
check "the team file sets the threshold" '"Strong"' 'r.values.unattended_min_badge' "$team"
check "the team file sets the history window" '250' 'r.values.history_commits' "$team"
check "a team list replaces the default list" '["release-bot"]' 'r.values.exclude_authors' "$team"
check "the source names the team layer" '"team"' 'r.source.history_commits' "$team"
check "--no-config skips the team file" '"Speculative"' 'r.values.unattended_min_badge' "$team" --no-config

local_repo="$(repo_with personal)"
cp "$team/docs/conventions/architecture.yaml" "$local_repo/docs/conventions/architecture.yaml"
cat >"$local_repo/docs/conventions/architecture.local.yaml" <<'YAML'
improve:
  unattended_min_badge: Worth exploring
YAML
check "the personal file beats the team file" '"Worth exploring"' 'r.values.unattended_min_badge' "$local_repo"
check "a key the personal file leaves out keeps the team value" '250' 'r.values.history_commits' "$local_repo"

moved="$(repo_with moved)"
mkdir -p "$moved/conventions"
printf 'improve:\n  history_commits: 40\n' >"$moved/conventions/architecture.yaml"
check "--home names the convention home" '40' 'r.values.history_commits' "$moved" --home conventions

bad="$(repo_with bad)"
printf 'improve:\n  unattended_min_badge: Excellent\n  history_commits: 0\n' >"$bad/docs/conventions/architecture.yaml"
check "a badge outside the three bands falls back to the default" '"Speculative"' 'r.values.unattended_min_badge' "$bad"
check "a history window below 1 falls back to the default" '100' 'r.values.history_commits' "$bad"
check "each rejected value is reported" '2' 'r.errors.length' "$bad"

other="$(repo_with other)"
printf 'verification: standard\nlayout:\n  min_revs: 0\n' >"$other/docs/conventions/architecture.yaml"
check "an error in another key's settings is not this skill's to report" '[]' 'r.errors' "$other"

code=0
node "$SUT" --unknown >/dev/null 2>&1 || code=$?
if [[ "$code" == 2 ]]; then
  echo "ok: an unknown argument exits 2"
else
  echo "FAIL: an unknown argument exited $code, not 2" >&2
  failed=1
fi

exit "$failed"
