#!/usr/bin/env bash
# Contract tests for the guardrails lefthook remote (git-hooks/lefthook-remote.yml): every job
# names a script under the repository root's .lefthook/<event>/, where lefthook looks up a
# remote's scripts, and that script runs an entry script that exists; no job takes a shared-copy
# job name (guardrails-<entry>), which lefthook would merge into one broken job; entries.json's
# remote names this file. With lefthook on PATH, a consumer whose lefthook.yml carries the
# snippet `install.mjs plan --scope remote` returns, fetched from a local stand-in for this
# repository, verifies ok and blocks an off-convention subject, a staged secret and (with jq)
# a pushed citation of a deleted path, reading the consumer's own files; the consumer fetches
# the release branch, so a commit on main reaches it only once that branch moves.
# test-scope: plugins/guardrails/git-hooks/lefthook-remote.yml plugins/guardrails/git-hooks/entries.json plugins/guardrails/lib/git-hooks/install.mjs plugins/guardrails/git-hooks/commit-msg-convention.sh plugins/guardrails/git-hooks/pre-commit-content.sh plugins/guardrails/git-hooks/reference-verify.sh .lefthook/commit-msg/guardrails-commit-msg-convention.sh .lefthook/pre-commit/guardrails-pre-commit-content.sh .lefthook/pre-push/guardrails-reference-verify.sh .github/scripts/guardrails-release-ref/install-lefthook.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA LEFTHOOK

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
TOP="$(cd "$PLUGIN/../.." && pwd)"
CONFIG="$HERE/lefthook-remote.yml"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"

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

# jobs: "<event> <name> <script>" per job in the remote config.
jobs="$(awk '
  /^[a-z-]+:$/ { event = substr($0, 1, length($0) - 1) }
  /^ *- name: / { name = $3 }
  /^ *script: / { print event, name, $2 }
' "$CONFIG")"
expect "the remote config has one job per entry event" "commit-msg pre-commit pre-push" \
  "$(cut -d' ' -f1 <<<"$jobs" | sort | xargs)"
while read -r event name script; do
  wrapper="$TOP/.lefthook/$event/$script"
  expect "$name: its script is under .lefthook/$event/" yes "$([[ -f "$wrapper" ]] && echo yes)"
  # shellcheck disable=SC2016 # matches the wrapper's literal text
  target="$(sed -n 's#^exec bash "${BASH_SOURCE\[0\]%/\*}/\(.*\)" "\$@"$#\1#p' "$wrapper" 2>/dev/null)"
  expect "$name: its script runs an entry script that exists" yes \
    "$([[ -n "$target" && -f "$TOP/.lefthook/$event/$target" ]] && echo yes)"
  entry="${script#guardrails-}"
  expect "$name: not a shared-copy job name" yes "$([[ "$name" != "guardrails-${entry%.sh}" ]] && echo yes)"
done <<<"$jobs"
expect "entries.json's remote names this config" "plugins/guardrails/git-hooks/lefthook-remote.yml" \
  "$(jq -r '.remote.config' "$HERE/entries.json" 2>/dev/null || sed -n 's/.*"config": "\(.*\)".*/\1/p' "$HERE/entries.json")"

if ! command -v lefthook >/dev/null 2>&1; then
  # CI sets this, so the end-to-end cases fail there rather than skip green.
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

# The stand-in: this checkout's plugin and .lefthook/ in a repository git reaches for $URL.
SRC="$WORK/src"
mkdir -p "$SRC/plugins"
cp -R "$PLUGIN" "$SRC/plugins/guardrails"
cp -R "$TOP/.lefthook" "$SRC/.lefthook"
git init -q -b main "$SRC"
git -C "$SRC" add -A
git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -m src --no-verify
REF="$(jq -r '.remote.ref' "$HERE/entries.json" 2>/dev/null)"
[[ -n "$REF" && "$REF" != null ]] || REF="$(sed -n 's/.*"ref": "\(.*\)".*/\1/p' "$HERE/entries.json")"
git -C "$SRC" branch "$REF"
git config --global "url.file://$SRC.insteadOf" "$URL"

REPO="$WORK/consumer"
git init -q --bare -b main "$WORK/consumer.git"
git init -q -b main "$REPO"
git -C "$REPO" config user.name t
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" remote add origin "$WORK/consumer.git"
mkdir -p "$REPO/.claude"
printf '## subject_pattern\n^[A-Z]+-[0-9]+: .+\n' >"$REPO/.claude/source-control.md"
node -e 'const p = JSON.parse(process.argv[1]); console.log(p.decisions.find((d) => d.kind === "lefthook-config").snippet)' \
  "$(node "$INSTALL" plan --scope remote --repo "$REPO")" >"$REPO/lefthook.yml"
(cd "$REPO" && lefthook install >/dev/null 2>&1)
expect "lefthook install fetches the remote and verify reports every entry ok" "ok ok ok" \
  "$(node "$INSTALL" verify --repo "$REPO" | cut -f1 | xargs)"

git -C "$REPO" add -A
git -C "$REPO" commit -q -m "feat: off convention" >/dev/null 2>&1
expect "commit-msg: an off-convention subject blocks" 1 "$?"
git -C "$REPO" commit -q -m "ABC-1: seed" >/dev/null 2>&1
expect "commit-msg: a subject on the consumer's pattern passes" 0 "$?"
git -C "$REPO" push -q origin main >/dev/null 2>&1
git -C "$REPO" remote set-head origin main >/dev/null

printf 'a\ntoken=ghp_%s\n' "$(printf 'A%.0s' {1..36})" >"$REPO/notes.md"
git -C "$REPO" add notes.md
err="$(git -C "$REPO" commit -q -m "ABC-2: notes" 2>&1 >/dev/null)"
expect "pre-commit: a staged token blocks, naming the consumer's line" yes \
  "$(grep -q 'notes.md:2: secret or credential pattern' <<<"$err" && echo yes)"
git -C "$REPO" rm -q --cached notes.md
rm "$REPO/notes.md"

if command -v jq >/dev/null 2>&1; then
  mkdir -p "$REPO/docs"
  printf 'gone\n' >"$REPO/docs/gone.md"
  git -C "$REPO" add docs
  git -C "$REPO" commit -q -m "ABC-3: add" >/dev/null 2>&1
  git -C "$REPO" rm -q docs/gone.md
  git -C "$REPO" commit -q -m "ABC-4: remove" >/dev/null 2>&1
  git -C "$REPO" push -q origin main >/dev/null 2>&1
  # Pushed from another branch, so only the refs lefthook passes on stdin name main's range.
  # shellcheck disable=SC2016 # the backticks are Markdown, not a substitution
  printf 'See `docs/gone.md`.\n' >"$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -q -m "ABC-5: cite" >/dev/null 2>&1
  git -C "$REPO" switch -q -c side
  err="$(git -C "$REPO" push origin main 2>&1)"
  expect "pre-push: a pushed citation of a deleted path blocks, from the refs on stdin" yes \
    "$(grep -q 'README.md:1: stale-path-verify' <<<"$err" && echo yes)"
elif [[ "${GUARDRAILS_REQUIRE_LEFTHOOK:-}" == 1 ]]; then
  expect "jq is on PATH for the pre-push case" yes no
else
  echo "SKIP: jq not on PATH -- the pre-push case skipped"
fi

# The consumer fetches the release branch, never main: an unreleased commit on main stays out
# until the branch fast-forwards to it.
CACHED="$REPO/.git/info/lefthook-remotes/claude-code-plugins-${REF//-/--}/plugins/guardrails/git-hooks/lefthook-remote.yml"
echo "# unreleased" >>"$SRC/plugins/guardrails/git-hooks/lefthook-remote.yml"
git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -am unreleased --no-verify
(cd "$REPO" && lefthook install >/dev/null 2>&1)
expect "an unreleased commit on main does not reach the consumer" no \
  "$(grep -q '# unreleased' "$CACHED" && echo yes || echo no)"
git -C "$SRC" branch -f "$REF" main
(cd "$REPO" && lefthook install >/dev/null 2>&1)
expect "after the release branch moves, lefthook install fetches it" yes \
  "$(grep -q '# unreleased' "$CACHED" && echo yes || echo no)"

echo "lefthook-remote: $PASS passed, $FAIL failed"
((FAIL == 0))
