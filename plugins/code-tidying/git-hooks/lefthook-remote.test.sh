#!/usr/bin/env bash
# test-scope: plugins/code-tidying/git-hooks/lefthook-remote.yml plugins/code-tidying/git-hooks/entries.json plugins/code-tidying/lib/git-hooks/install.mjs plugins/code-tidying/git-hooks/comment-lint.sh plugins/code-tidying/git-hooks/comment-lint.py .lefthook/pre-commit/code-tidying-comment-lint.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA LEFTHOOK
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
TOP="$(cd "$PLUGIN/../.." && pwd)"
CONFIG="$HERE/lefthook-remote.yml"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
SH="$(command -v dash)" || SH="sh"

PASS=0
FAIL=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

jobs="$(awk '
  /^[a-z-]+:$/ { event = substr($0, 1, length($0) - 1) }
  /^ *- name: / { name = $3 }
  /^ *script: / { print event, name, $2 }
' "$CONFIG")"
expect "the remote config has one pre-commit job per entry" "pre-commit" "$(cut -d' ' -f1 <<<"$jobs" | sort | xargs)"
GUARD="$(mktemp -d)"
trap 'rm -rf "$GUARD"' EXIT
while read -r event name script; do
  wrapper="$TOP/.lefthook/$event/$script"
  expect "$name: its script is under .lefthook/$event/" yes "$([[ -f "$wrapper" ]] && echo yes)"
  # shellcheck disable=SC2016 # matches the wrapper's literal text
  target="$(sed -n 's#^exec sh "${src%/\*}/\(.*\)" "\$@"$#\1#p' "$wrapper" 2>/dev/null)"
  expect "$name: its script runs an entry script that exists" yes \
    "$([[ -n "$target" && -f "$TOP/.lefthook/$event/$target" ]] && echo yes)"
  expect "$name: the job's runner is sh" yes \
    "$(awk -v s="$script" '$1 == "script:" { hit = ($2 == s) } hit && $1 == "runner:" { print ($2 == "sh" ? "yes" : "no"); exit }' "$CONFIG")"
  for root in "$GUARD/wt" "$GUARD/git/info/lefthook-remotes/r"; do
    mkdir -p "$root/.lefthook/$event" "$(dirname "$root/.lefthook/$event/$target")"
    cp "$wrapper" "$root/.lefthook/$event/$script"
    printf '#!/bin/sh\necho ran\n' >"$root/.lefthook/$event/$target"
  done
  out="$("$SH" "$GUARD/wt/.lefthook/$event/$script" </dev/null 2>&1)"
  expect "$name: the work-tree copy exits 0 without running the entry script" "0:" "$?:$out"
  out="$("$SH" "$GUARD/git/info/lefthook-remotes/r/.lefthook/$event/$script" </dev/null 2>&1)"
  expect "$name: the fetched copy runs the entry script" "ran" "$out"
  win="$GUARD/git\\info\\lefthook-remotes\\r\\.lefthook\\$event\\$script"
  cp "$wrapper" "$win"
  out="$("$SH" "$win" </dev/null 2>&1)"
  expect "$name: the fetched copy runs from a backslash path" "ran" "$out"
  entry="${script#code-tidying-}"
  expect "$name: not a shared-copy job name" yes "$([[ "$name" != "code-tidying-${entry%.sh}" ]] && echo yes)"
done <<<"$jobs"
rm -rf "$GUARD"
expect "entries.json's remote names this config" "plugins/code-tidying/git-hooks/lefthook-remote.yml" \
  "$(jq -r '.remote.config' "$HERE/entries.json" 2>/dev/null || sed -n 's/.*"config": "\(.*\)".*/\1/p' "$HERE/entries.json")"

if ! command -v lefthook >/dev/null 2>&1; then
  if [[ "${GUARDRAILS_REQUIRE_LEFTHOOK:-}" == 1 ]]; then
    echo "FAIL: lefthook not on PATH, and GUARDRAILS_REQUIRE_LEFTHOOK=1 requires the end-to-end cases" >&2
    exit 1
  fi
  echo "SKIP: lefthook not on PATH -- remote end-to-end cases skipped"
  echo "lefthook-remote: $PASS passed, $FAIL failed"
  ((FAIL == 0))
  exit
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/gitconfig" GIT_CONFIG_NOSYSTEM=1
URL="https://github.com/melodic-software/claude-code-plugins"

PY=""
while IFS= read -r candidate; do
  if "$candidate" -c 'import pygments' >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done < <(type -ap python3)
if [[ -z "$PY" ]]; then
  echo "SKIP: no python3 on PATH imports pygments -- remote end-to-end cases skipped"
  echo "lefthook-remote: $PASS passed, $FAIL failed"
  ((FAIL == 0))
  exit
fi
mkdir -p "$WORK/py"
ln -s "$PY" "$WORK/py/python3"
export PATH="$WORK/py:$PATH"

SRC="$WORK/src"
mkdir -p "$SRC/plugins"
cp -R "$PLUGIN" "$SRC/plugins/code-tidying"
cp -R "$TOP/.lefthook" "$SRC/.lefthook"
git init -q -b main "$SRC"
git -C "$SRC" add -A
git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -m src --no-verify
REF="$(jq -r '.remote.ref' "$HERE/entries.json" 2>/dev/null)"
[[ -n "$REF" && "$REF" != null ]] || REF="$(sed -n 's/.*"ref": "\(.*\)".*/\1/p' "$HERE/entries.json")"
expect "entries.json's remote tracks main" main "$REF"
git config --global "url.file://$SRC.insteadOf" "$URL"

REPO="$WORK/consumer"
git init -q -b main "$REPO"
git -C "$REPO" config user.name t
git -C "$REPO" config user.email t@example.invalid
mkdir -p "$REPO/docs/conventions"
printf 'comment_lint: block\n' >"$REPO/docs/conventions/code-tidying.yaml"
node -e 'const p = JSON.parse(process.argv[1]); console.log(p.decisions.find((d) => d.kind === "lefthook-config").snippet)' \
  "$(node "$INSTALL" plan --scope remote --repo "$REPO")" >"$REPO/lefthook.yml"
(cd "$REPO" && lefthook install >/dev/null 2>&1)
expect "lefthook install fetches the remote and verify reports the entry ok" "ok" \
  "$(node "$INSTALL" verify --repo "$REPO" | cut -f1 | xargs)"

git -C "$REPO" add -A
git -C "$REPO" commit -q -m seed >/dev/null 2>&1
expect "pre-commit: a commit with no comment passes" 0 "$?"
printf 'x=1\n# a planted note\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
err="$(git -C "$REPO" commit -q -m note 2>&1 >/dev/null)"
expect "pre-commit: an added comment outside the posture blocks, naming the consumer's line" yes \
  "$(grep -q '^run.sh:2: comment outside the necessary posture' <<<"$err" && echo yes)"
printf 'comment_lint: report\n' >"$REPO/docs/conventions/code-tidying.yaml"
git -C "$REPO" add -A
err="$(git -C "$REPO" commit -q -m report 2>&1 >/dev/null)"
expect "pre-commit: the consumer's report level prints and passes" "0|yes" \
  "$?|$(grep -q '^run.sh:2: comment outside' <<<"$err" && echo yes)"

echo "lefthook-remote: $PASS passed, $FAIL failed"
((FAIL == 0))
