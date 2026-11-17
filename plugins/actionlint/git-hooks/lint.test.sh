#!/usr/bin/env bash
# Contract tests for the actionlint lint entry (git-hooks/lint.sh): the
# actionlint adapter lints every GitHub Actions workflow file, with the root's
# optional actionlint config (https://github.com/kjanat/actionlint/blob/v1.17.0/docs/config.md#configuration-file); a
# finding blocks only on a line the commit adds; a finding about a whole
# workflow is attributed to the line actionlint names; a partly staged file is
# checked as staged; nothing is ever rewritten; only workflow files are linted;
# --worktree reports uncommitted changes; actionlint failing with no parseable
# finding fails closed; a .claude/ecosystems/ record never runs; a missing
# actionlint follows the skip-key rule; and the plugin's own vendored installer
# wires the entry, carrying over a decline of the entry it replaced.
# Expected values are actionlint's documented output (docs/checks.md): an
# undefined property in an expression, a job without runs-on, and a YAML parse
# error; the line numbers are counted by hand from the fixtures below. Config
# discovery (docs/config.md: actionlint.yaml or actionlint.yml in .github) was
# measured against actionlint 1.17.0: it reads the repository root's .github
# config only, and -stdin-filename keeps the config's paths: rules for stdin.
# test-scope: plugins/actionlint/git-hooks/entries.json plugins/actionlint/git-hooks/adapters.sh
# test-scope: plugins/actionlint/lib/git-hooks/check-lib.sh plugins/actionlint/lib/git-hooks/resolve-tool.sh plugins/actionlint/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v actionlint >/dev/null 2>&1; then
  echo "SKIP: actionlint not on PATH -- lint entry tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

CONFIG=$'self-hosted-runner:\n  labels: []\n'
n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  mkdir -p "$REPO/.github/workflows"
  case "${1:-}" in
  NONE) ;;
  yml) printf '%s' "$CONFIG" >"$REPO/.github/actionlint.yml" ;;
  *) printf '%s' "$CONFIG" >"$REPO/.github/actionlint.yaml" ;;
  esac
  printf 'seed\n' >"$REPO/seed.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}
record() {
  mkdir -p "$REPO/.claude/ecosystems"
  printf '%s\n' "$1" >"$REPO/.claude/ecosystems/github-actions.yaml"
  git -C "$REPO" add .claude/ecosystems/github-actions.yaml
  git -C "$REPO" commit -q -m record --no-verify
}

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/stublint" <<EOF
#!/bin/sh
: >"$WORK/stublint-ran"
for a in "\$@"; do printf '%s:2:5: X1 bad thing\n' "\$a"; done
exit 1
EOF
chmod +x "$BIN/stublint"

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && PATH="$BIN:$PATH" bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

HINT='actionlint: fix the findings actionlint reported above.'
CLEAN=$'name: ok\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n'
# Line 7 reads an undefined property: actionlint [expression] "property ... is not defined".
# shellcheck disable=SC2016 # literal workflow YAML: ${{ }} must stay unexpanded
BAD=$'name: bad\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "${{ steps.missing.outputs.x }}"\n'
MSG='property "missing" is not defined in object type {} [expression]'
WF=.github/workflows

new_repo NONE
expect "--resolve reports no adapter in a repository with no workflow files" "actionlint	lint	none		n/a	no GitHub Actions workflow files" \
  "$(cd "$REPO" && HOME="$WORK/home" bash "$CHECK" --resolve)"
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "workflows and no actionlint config: actionlint lints on its defaults" "1||$WF/ci.yml:7: $MSG
$HINT" "$(check "$REPO")"
expect "--resolve reports the adapter with no config" "actionlint	lint	adapter:actionlint	actionlint	yes	config none (actionlint defaults); binary actionlint on PATH" \
  "$(cd "$REPO" && HOME="$WORK/home" bash "$CHECK" --resolve)"

new_repo yml
printf 'paths:\n  .github/workflows/ci.yml:\n    ignore: ["is not defined"]\n' >"$REPO/.github/actionlint.yml"
git -C "$REPO" add .github/actionlint.yml
git -C "$REPO" commit -q -m config --no-verify
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "an actionlint.yml config is applied: its paths: ignore rule holds" "0||" "$(check "$REPO")"

new_repo
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "a clean staged workflow passes with no output" "0||" "$(check "$REPO")"
expect "--resolve reports the adapter, its config and that actionlint is found" "actionlint	lint	adapter:actionlint	actionlint	yes	config .github/actionlint.yaml; binary actionlint on PATH" \
  "$(cd "$REPO" && HOME="$WORK/home" bash "$CHECK" --resolve)"

# actionlint reads its config from the work tree; the commit holds the index's.
DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
printf 'self-hosted-runner:\n  labels: [x]\n' >"$REPO/.github/actionlint.yaml"
expect "an actionlint config edited after staging refuses the commit, naming it" "1||.github/actionlint.yaml: $DRIFT" "$(check "$REPO")"
git -C "$REPO" add .github/actionlint.yaml
rm "$REPO/.github/actionlint.yaml"
expect "an actionlint config staged then deleted refuses the commit, naming it" "1||.github/actionlint.yaml: $DRIFT" "$(check "$REPO")"
git -C "$REPO" checkout -q -- .github/actionlint.yaml
expect "with the config restored the commit passes" "0||" "$(check "$REPO")"

new_repo
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "a finding on an added line blocks, naming path and line" "1||$WF/ci.yml:7: $MSG
$HINT" "$(check "$REPO")"
expect "nothing is rewritten: the file keeps its bytes" "$(printf '%s' "$BAD")" "$(cat "$REPO/$WF/ci.yml")"
expect "nothing is rewritten: the index keeps its bytes" "$(printf '%s' "$BAD")" "$(git -C "$REPO" show :"$WF/ci.yml")"

new_repo
printf '%s' "$BAD" >"$REPO/$WF/ci.yaml"
git -C "$REPO" add "$WF/ci.yaml"
expect "a .yaml workflow is linted too" "1||$WF/ci.yaml:7: $MSG
$HINT" "$(check "$REPO")"

new_repo
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
git -C "$REPO" commit -q -m old --no-verify
printf '%s' "${BAD/name: bad/name: renamed}" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

# A finding about a whole workflow (a job with no runs-on) is attributed to the
# line actionlint names for it, which is line 4, the job's key.
NORUNS=$'name: w\non: push\njobs:\n  build:\n    steps:\n      - run: echo ok\n'
new_repo
printf '%s' "$NORUNS" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "a whole-workflow finding is attributed to the line actionlint names" "1||$WF/ci.yml:4: \"runs-on\" section is missing in job \"build\" [syntax-check]
$HINT" "$(check "$REPO")"
git -C "$REPO" commit -q -m old --no-verify
printf '%s' "${NORUNS/echo ok/echo changed}" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "the same finding does not block when the commit leaves its line alone" "0||" "$(check "$REPO")"
printf '%s' "${NORUNS/build:/test:}" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "it blocks again once the commit changes that line" "1||$WF/ci.yml:4: \"runs-on\" section is missing in job \"test\" [syntax-check]
$HINT" "$(check "$REPO")"

new_repo
printf 'name: x\non: [push\njobs: {}\n' >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "a YAML parse error is reported at its line" "1||$WF/ci.yml:3: could not parse as YAML: did not find expected ',' or ']' [syntax-check]
$HINT" "$(check "$REPO")"

# The embedded ShellCheck run is off: SC2045 (iterating over ls output) is a
# ShellCheck-only finding that actionlint reports when the integration is on.
# shellcheck disable=SC2016 # literal workflow YAML: $(ls) must stay unexpanded
SHELLISH=$'name: s\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          for f in $(ls); do echo "$f"; done\n'
new_repo
printf '%s' "$SHELLISH" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "the embedded ShellCheck integration stays off" "0||" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/sub/.github/workflows"
printf '%s' "$BAD" >"$REPO/sub/.github/workflows/ci.yml"
git -C "$REPO" add sub/.github/workflows/ci.yml
expect "a workflow under a nested .github/workflows is linted under the root config" "1||sub/.github/workflows/ci.yml:7: $MSG
$HINT" "$(check "$REPO")"

new_repo
printf '%s' "$BAD" >"$REPO/other.yml"
printf '%s' "$BAD" >"$REPO/.github/not-a-workflow.yml"
printf '%s' "$BAD" >"$REPO/$WF/notes.txt"
git -C "$REPO" add other.yml .github/not-a-workflow.yml "$WF/notes.txt"
expect "YAML outside .github/workflows and other extensions are not linted" "0||" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/.githooks/actionlint/.github/workflows"
printf '%s' "$BAD" >"$REPO/.githooks/actionlint/.github/workflows/copy.yml"
git -C "$REPO" add -f .githooks/actionlint/.github/workflows/copy.yml
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"

# Partly staged: the index is what is committed, so the index is what is linted.
new_repo
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
expect "a partly staged file is linted as staged: the staged finding blocks" "1||$WF/ci.yml:7: $MSG
$HINT" "$(check "$REPO")"
expect "a partly staged file is left byte for byte" "$(printf '%s' "$CLEAN")" "$(cat "$REPO/$WF/ci.yml")"
new_repo
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
expect "a finding only in the unstaged edit does not block" "0||" "$(check "$REPO")"
new_repo
printf 'paths:\n  .github/workflows/ci.yml:\n    ignore: ["is not defined"]\n' >"$REPO/.github/actionlint.yaml"
git -C "$REPO" add .github/actionlint.yaml
git -C "$REPO" commit -q -m config --no-verify
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
expect "a partly staged file keeps the config's paths: ignore rules" "0||" "$(check "$REPO")"

new_repo
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
rm "$REPO/$WF/ci.yml"
expect "staged then deleted from the work tree: the staged finding still blocks" "1||$WF/ci.yml:7: $MSG
$HINT" "$(check "$REPO")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/$WF/ci.yml" ]] && echo yes || echo no)"
ln -s missing.yml "$REPO/$WF/link.yml"
git -C "$REPO" add "$WF/link.yml"
git -C "$REPO" rm -q --cached "$WF/ci.yml"
rm "$REPO/$WF/link.yml"
expect "staged then deleted: a staged symlink is not checked" "0||" "$(check "$REPO")"

new_repo
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
git -C "$REPO" commit -q -m clean --no-verify
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
expect "--worktree: an uncommitted finding blocks" "1||$WF/ci.yml:7: $MSG
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$(printf '%s' "$BAD")" "$(cat "$REPO/$WF/ci.yml")"
git -C "$REPO" checkout -q "$WF/ci.yml"
printf '%s' "$BAD" >"$REPO/$WF/new.yml"
expect "--worktree: an untracked workflow is checked whole" "1||$WF/new.yml:7: $MSG
$HINT" "$(check "$REPO" --worktree)"
rm "$REPO/$WF/new.yml"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

new_repo
printf 'self-hosted-runner: [\n' >"$REPO/.github/actionlint.yaml"
git -C "$REPO" add .github/actionlint.yaml
git -C "$REPO" commit -q -m broken --no-verify
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
got="$(check "$REPO")"
expect "an unparsable config fails closed, naming actionlint's exit" "1||actionlint: actionlint exited 3 and reported no <path>:<line> finding, so the change was not checked:" "${got%%$'\n'*}"
expect "the fail-closed output carries actionlint's own message" yes "$([[ "$got" == *'could not parse config file'* ]] && echo yes)"

new_repo
record 'globs: [".github/workflows/*.yml"]
lint-cmd: "stublint <files>"'
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "with a record and the config, actionlint lints and the record's linter never runs" "0||" "$(check "$REPO")"
new_repo NONE
record 'globs: [".github/workflows/*.yml"]
lint-cmd: "stublint <files>"'
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
expect "with a record and no config, actionlint lints and the record's linter never runs" "0||" "$(check "$REPO")"
expect "--resolve names the record and where it runs" "actionlint	lint	adapter:actionlint	actionlint	yes	config none (actionlint defaults); binary actionlint on PATH; the github-actions record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && HOME="$WORK/home" bash "$CHECK" --resolve)"
expect "the record's linter never ran" no "$([[ -e "$WORK/stublint-ran" ]] && echo yes || echo no)"

# A PATH with the tools the script runs, git and no actionlint.
NOLINT="$WORK/nolint"
mkdir -p "$NOLINT"
for t in git bash sed awk cat mktemp rm dirname grep tr; do
  ln -s "$(command -v "$t")" "$NOLINT/$t"
done
INSTALL_HINT='the kjanat/actionlint v1.17.0 release asset, checked against its checksums file: https://github.com/kjanat/actionlint/releases/tag/v1.17.0'
new_repo
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOLINT" bash "$CHECK" 2>&1)"
expect "missing actionlint: an agent fails with the install command" "1" "$?"
expect "missing actionlint: the message names the tool and the skip key" \
  "FAIL: actionlint missing. Install: $INSTALL_HINT
To skip only while actionlint is missing: git -c checks.skipmissing=actionlint commit ..." "$out"
out="$(cd "$REPO" && PATH="$NOLINT" bash "$CHECK" 2>&1)"
expect "missing actionlint: a person gets a notice and exit 0" "0|NOTICE: actionlint missing, so this check did not run. Install: $INSTALL_HINT" "$?|$out"
git -C "$REPO" config checks.skipmissing actionlint
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOLINT" bash "$CHECK" 2>&1)"
expect "missing actionlint named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: actionlint (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOLINT" bash "$CHECK" --worktree 2>&1)"
expect "missing actionlint named in checks.skipmissing, --worktree: skipped with a line" "0|SKIPPED: actionlint (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOLINT" bash "$CHECK" --worktree 2>&1)"
expect "missing actionlint, --worktree: an agent fails as at commit time" \
  "1|FAIL: actionlint missing. Install: $INSTALL_HINT" "$?|${out%%$'\n'*}"
new_repo NONE
printf 'x\n' >"$REPO/notes.txt"
git -C "$REPO" add notes.txt
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOLINT" bash "$CHECK" 2>&1)"
expect "missing actionlint and no workflow file staged: nothing is asked of the host" "0|" "$?|$out"

# End to end through the plugin's vendored installer and real commits.
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
new_repo
git -C "$REPO" config checks.actionlint.actionlint-check.declined true
expect "a decline of the old actionlint-check entry carries over to lint" "declined	lint" "$(node "$INSTALL" verify --repo "$REPO" | cut -f1,2)"
git -C "$REPO" config --unset checks.actionlint.actionlint-check.declined
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the lint entry" '[{"entry":"lint","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# actionlint lint sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/actionlint/lint.sh") && echo yes)"
printf '%s' "$BAD" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "$WF/ci.yml:7: $MSG" "$(printf '%s\n' "$err" | head -1)"
printf '%s' "$CLEAN" >"$REPO/$WF/ci.yml"
git -C "$REPO" add "$WF/ci.yml"
git -C "$REPO" commit -q -m fixed >/dev/null 2>&1
expect "git commit succeeds once the workflow is clean" "0" "$?"
expect "verify reports ok after the install" "ok	lint" "$(node "$INSTALL" verify --repo "$REPO" | cut -f1,2)"

echo "lint: $PASS passed, $FAIL failed"
((FAIL == 0))
