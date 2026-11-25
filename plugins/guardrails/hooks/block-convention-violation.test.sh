#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/*.test.sh plugins/guardrails/hooks/workflow-resilience-check.sh

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-convention-violation.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

newrepo() {
  local d
  d="$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")"
  git -C "$d" init -q -b main
  if [[ -n "${1:-}" ]]; then
    mkdir -p "$d/docs/conventions"
    printf '%s\n' "$1" >"$d/docs/conventions/source-control.yaml"
    git -C "$d" add docs/conventions/source-control.yaml
  fi
  printf '%s' "$d"
}
addfolder() {
  mkdir -p "$1/docs/conventions/source-control"
  printf '%s\n' "$2" >"$1/docs/conventions/source-control/commit-convention.yml"
  git -C "$1" add docs/conventions/source-control/commit-convention.yml
}

GUARD_UNDER_TEST="$HOOK"

run() {
  local label="$1" repo="$2" command="$3" expected="$4" tool="${5:-Bash}"
  expect "$label" "$expected" --tool "$tool" --command "$command" --cwd "$repo" \
    -- "CLAUDE_PROJECT_DIR=$repo"
}

TICKET=$'subject_pattern: \047^[A-Z]+-[0-9]+: .+\047\npr_title_pattern: "Same as `subject_pattern`."'
CC='subject_pattern: Conventional Commits'
PCRE=$'subject_pattern: \047^(?:feat|fix): .+\047'

GOOD_COMMIT=$'git commit -F - --cleanup=verbatim <<\'EOF\'\nABC-123: do the thing\n\nBody line.\nEOF'
BAD_COMMIT=$'git commit -F - --cleanup=verbatim <<\'EOF\'\njunk subject\n\nBody line.\nEOF'

r="$(newrepo "")"
run "no team file: violating subject allowed" "$r" "$BAD_COMMIT" 0
r="$(newrepo 'trailer_policy: none')"
run "key absent: violating subject allowed" "$r" "$BAD_COMMIT" 0
r="$(newrepo "$PCRE")"
run "PCRE pattern: non-enforceable, allowed" "$r" "$BAD_COMMIT" 0
r="$(newrepo "")"
mkdir -p "$r/.claude"
printf '%s\n' $'## subject_pattern\n^[A-Z]+-[0-9]+: .+' >"$r/.claude/source-control.md"
git -C "$r" add .claude/source-control.md
run "retired markdown: a tracked .claude/source-control.md pattern is not enforced" "$r" "$BAD_COMMIT" 0

r="$(newrepo "$TICKET")"
run "ticket pattern: conforming subject allowed" "$r" "$GOOD_COMMIT" 0
run "ticket pattern: violating subject blocked" "$r" "$BAD_COMMIT" 2
run "ticket pattern: wsl-wrapped violating stdin subject blocked" "$r" "wsl ${BAD_COMMIT}" 2
run "ticket pattern: wsl-wrapped conforming stdin subject allowed" "$r" "wsl ${GOOD_COMMIT}" 0
run "ticket pattern: violating subject in prose (no commit) allowed" "$r" "echo 'junk subject'" 0
run "ticket pattern: git status is not a commit, allowed" "$r" "git status --short" 0

GIT_SHIM="$TEST_TMPDIR/git-shim"
mkdir -p "$GIT_SHIM"
GIT_LOG="$TEST_TMPDIR/git-spawns"
REAL_GIT="$(command -v git)"
{
  printf '#!%s\n' "$(command -v bash)"
  printf 'printf "%%s\\n" "$*" >>%q\n' "$GIT_LOG"
  printf 'exec %q "$@"\n' "$REAL_GIT"
} >"$GIT_SHIM/git"
chmod +x "$GIT_SHIM/git"
: >"$GIT_LOG"
json=$(jq -n --arg c "echo hello" --arg d "$r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
CLAUDE_PROJECT_DIR="$r" PATH="$GIT_SHIM:$PATH" bash "$HOOK" <<<"$json" >/dev/null 2>&1
assert_eq "echo hello forks git zero times" "0" "$(wc -l <"$GIT_LOG" | tr -d ' ')"
: >"$GIT_LOG"
json=$(jq -n --arg c "git status --short" --arg d "$r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
CLAUDE_PROJECT_DIR="$r" PATH="$GIT_SHIM:$PATH" bash "$HOOK" <<<"$json" >/dev/null 2>&1
assert_eq "git status forks git zero times" "0" "$(wc -l <"$GIT_LOG" | tr -d ' ')"
: >"$GIT_LOG"
json=$(jq -n --arg c "$BAD_COMMIT" --arg d "$r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
CLAUDE_PROJECT_DIR="$r" PATH="$GIT_SHIM:$PATH" bash "$HOOK" <<<"$json" >/dev/null 2>&1 || true
if (($(wc -l <"$GIT_LOG" | tr -d ' ') > 0)); then
  ok "a commit still reaches git (repo_root / sequencer)"
else
  bad "a commit forked git zero times — the shim never ran, so the zeros above cannot discriminate"
fi
r="$(newrepo "$CC")"
run "CC keyword: conforming feat: subject allowed" "$r" \
  $'git commit -F - <<\'EOF\'\nfeat: add thing\nEOF' 0
run "CC keyword: violating subject blocked" "$r" "$BAD_COMMIT" 2

r="$(newrepo "$TICKET")"
addfolder "$r" "$CC"
run "team yaml: conforming subject allowed" "$r" "$GOOD_COMMIT" 0
run "team yaml: violating subject blocked" "$r" "$BAD_COMMIT" 2
run "team yaml: a subject only the folder form allows is blocked" "$r" \
  $'git commit -F - <<\'EOF\'\nfeat: add thing\nEOF' 2
run "team yaml: conforming PR title allowed" "$r" \
  "gh pr create --title 'ABC-9: ship it' --body-file b.md" 0
run "team yaml: violating PR title blocked" "$r" \
  "gh pr create --title 'junk title' --body-file b.md" 2

personal_repo() {
  local d
  d="$(newrepo "${1:-}")"
  git -C "$d" config core.excludesFile "$TEST_TMPDIR/no-global-excludes"
  mkdir -p "$d/docs/conventions"
  printf '%s\n' "subject_pattern: '^[A-Z]+-[0-9]+: .+'" >"$d/docs/conventions/source-control.local.yaml"
  printf '%s\n' 'docs/conventions/**/*.local.*' >"$d/.gitignore"
  printf '%s' "$d"
}
r="$(personal_repo "")"
run "personal layer, no team pattern: conforming subject allowed" "$r" "$GOOD_COMMIT" 0
run "personal layer, no team pattern: violating subject blocked" "$r" "$BAD_COMMIT" 2
run "personal layer: a PR title is never gated by it" "$r" \
  "gh pr create --title 'junk title' --body-file b.md" 0
r="$(personal_repo "$CC")"
run "personal layer under a team pattern: a subject only the team allows passes" "$r" \
  $'git commit -F - <<\'EOF\'\nfeat: add thing\nEOF' 0
run "personal layer under a team pattern: a subject only the personal file allows is blocked" "$r" \
  "$GOOD_COMMIT" 2

r="$(newrepo "$TICKET")"
run "--amend exempt" "$r" "git commit --amend --no-edit" 0
run "-C exempt" "$r" "git commit -C HEAD~1" 0
run "--fixup exempt" "$r" "git commit --fixup abc123" 0
run "-F path exempt (message not on command line)" "$r" "git commit -F msg.txt" 0
run "-m form not stdin-form (mechanic gate's concern), allowed here" "$r" \
  "git commit -m 'junk subject'" 0

r="$(newrepo "$TICKET")"
git -C "$r" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
mkdir -p "$(git -C "$r" rev-parse --absolute-git-dir)"
touch "$(git -C "$r" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "sequencer: violating subject allowed mid-merge" "$r" "$BAD_COMMIT" 0

r="$(newrepo "$TICKET")"
run "printf | git commit -F -: unreadable content, allowed" "$r" \
  "printf 'junk subject' | git commit -F -" 0

r="$(newrepo "$TICKET")"
run "gh pr create: conforming --title allowed" "$r" \
  "gh pr create --title 'ABC-9: ship it' --body-file b.md" 0
run "gh pr create: violating --title blocked" "$r" \
  "gh pr create --title 'junk title' --body-file b.md" 2
run "gh pr create: violating --title= blocked" "$r" \
  "gh pr create --title='junk title'" 2
run "gh pr create: no --title never blocked" "$r" "gh pr create --web" 0
run "gh pr edit --title out of scope, allowed" "$r" "gh pr edit 12 --title 'junk'" 0
r="$(newrepo $'subject_pattern: \047^[A-Z]+-[0-9]+: .+\047')"
run "no pr_title_pattern key: title not gated" "$r" "gh pr create --title 'junk'" 0

r="$(newrepo "$TICKET")"
PS_GOOD=$'@\'\nABC-77: powershell subject\n\'@ | git commit -F - --cleanup=verbatim'
PS_BAD=$'@\'\njunk subject\n\'@ | git commit -F - --cleanup=verbatim'
run "PS: conforming here-string subject allowed" "$r" "$PS_GOOD" 0 PowerShell
run "PS: violating here-string subject blocked" "$r" "$PS_BAD" 2 PowerShell
run "PS: violating gh pr create --title blocked" "$r" \
  "gh pr create --title 'junk title'" 2 PowerShell
PS_BAD_EXPANDABLE=$'@"\njunk subject $(node -p \'x\')\n"@ | git commit -F - --cleanup=verbatim'
run "PS: violating expandable here-string subject deferred (classifier rc 2)" "$r" \
  "$PS_BAD_EXPANDABLE" 0 PowerShell
run "PS: a commented here-string opener is refused here, not deferred (blocked)" "$r" \
  $'Write-Output x # @"\ngit commit -m x\n"@ fine"' 2 PowerShell
run "PS: the @\047 spelling of the commented opener (blocked)" "$r" \
  $'Write-Output x # @\'\ngit commit -m x\n\'@ fine\'' 2 PowerShell
run "PS: a commented opener behind a {} construct is refused (blocked)" "$r" \
  $'Write-Output {x} # @"\ngit commit -m x\n"@ fine"' 2 PowerShell
run "PS: a commented opener behind an iex is refused (blocked)" "$r" \
  $'iex a; Write-Output x # @"\ngit commit -m x\n"@ fine"' 2 PowerShell
run "PS: a commented opener behind a {} with no git in it (blocked, accepted over-block)" "$r" \
  $'Write-Output {x} # @"\nhello\n"@' 2 PowerShell
run "PS: a # inside a quoted string before a real opener (blocked, accepted over-block)" "$r" \
  $'Write-Output "#1" @"\nhello\n"@' 2 PowerShell
run "PS: a here-string body containing a # (allowed)" "$r" \
  $'Write-Output @\'\nrelease # 1\n\'@' 0 PowerShell
run "PS: conforming here-string subject with a trailing comment (allowed)" "$r" \
  "$PS_GOOD # ok" 0 PowerShell

run "PS: a quote on a confirmed opener prefix is refused here, not deferred (blocked)" "$r" \
  $'Write-Output "x" @"\ngit commit -m x\n"@' 2 PowerShell
run "PS: a backslash on a confirmed opener prefix is refused here, not deferred (blocked)" "$r" \
  $'Write-Output C:\\x @"\ngit commit -m x\n"@' 2 PowerShell
run "PS: a <# earlier than a confirmed opener is refused here, not deferred (blocked)" "$r" \
  $'<# hi\nWrite-Output @"\ngit commit -m x\n"@' 2 PowerShell
run "PS: a bare CR is refused here, not deferred (blocked)" "$r" \
  $'Write-Output hi\rgit commit -m x' 2 PowerShell
run "PS: CRLF canonical conforming here-string (allowed)" "$r" \
  "$(printf '%s\r\n%s\r\n%s' "@'" "ABC-123: subject" "'@ | git commit -F -")" 0 PowerShell

r="$(newrepo "$TICKET")"
run "leading-space subject validates RAW (blocked)" "$r" \
  $'git commit -F - --cleanup=verbatim <<\'EOF\'\n  ABC-123: spaced subject\nEOF' 2
run "env-assignment-prefixed gh pr create --title (blocked)" "$r" \
  "GH_PROMPT_DISABLED=1 gh pr create --title 'junk title'" 2
run "env-wrapper gh pr create --title (blocked)" "$r" \
  "env GH_TOKEN=x gh pr create --title 'junk title'" 2
run "inline alias commit: violating subject blocked" "$r" \
  $'git -c alias.c=commit c -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
r="$(newrepo "$TICKET")"
git -C "$r" config alias.qc commit
run "configured alias commit: violating subject blocked" "$r" \
  $'git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "configured alias commit: conforming subject allowed" "$r" \
  $'git qc -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0
r="$(newrepo "$TICKET")"
git -C "$r" config alias.whatchanged commit
run "deprecated builtin alias.whatchanged: violating subject blocked" "$r" \
  $'git whatchanged -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "deprecated builtin alias.whatchanged: conforming subject allowed" "$r" \
  $'git whatchanged -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0
r="$(newrepo "$TICKET")"
git -C "$r" config alias.bugreport commit
run "post-2.25 name alias.bugreport: violating subject blocked" "$r" \
  $'git bugreport -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "post-2.25 name alias.bugreport: conforming subject allowed" "$r" \
  $'git bugreport -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

subrepo() {
  local d="$1/$2"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  mkdir -p "$d/docs/conventions"
  printf '%s\n' "$TICKET" >"$d/docs/conventions/source-control.yaml"
  git -C "$d" add docs/conventions/source-control.yaml
  printf '%s' "$d"
}

r="$(newrepo "$TICKET")"
git -C "$r" config alias.qc commit
run "env -u -C git <alias>: alias resolves in the TRUE repo (blocked)" "$r" \
  $'env -u -C git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "env -u -C git <alias>: conforming subject still allowed" "$r" \
  $'env -u -C git qc -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

r="$(newrepo "$TICKET")"
d="$(subrepo "$r" git)"
git -C "$d" config alias.qc commit
run "env -u -C git <alias>: decoy repo at <cwd>/git is not read" "$r" \
  $'env -u -C git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 0

r="$(newrepo "$TICKET")"
d="$(subrepo "$r" dec)"
git -C "$d" config alias.qs 'commit -F - --cleanup=verbatim --'
run "post-subcommand -C is not a chdir (decoy repo not read)" "$r" \
  $'git qs -C dec <<\'EOF\'\njunk subject\nEOF' 0

r="$(newrepo "$TICKET")"
d="$(subrepo "$r" inner)"
git -C "$d" config alias.qc commit
run "env -C <dir> git <alias>: wrapper chdir is replayed (blocked)" "$r" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "env -C <dir> git <alias>: conforming subject still allowed" "$r" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

run "env --chdir=<dir> git <alias>: attached long form is replayed" "$r" \
  $'env --chdir=inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2

r3="$(newrepo "$TICKET")"
d3="$(subrepo "$r3" inner)"
git -C "$d3" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
touch "$(git -C "$d3" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "wrapper chdir reaches the sequencer probe (exempt mid-merge)" "$r3" \
  $'env --chdir=inner git commit -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 0
r4="$(newrepo "$TICKET")"
subrepo "$r4" inner >/dev/null
run "wrapper chdir, no sequencer: still content-gated" "$r4" \
  $'env --chdir=inner git commit -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2

r="$(newrepo "$TICKET")"
d="$(subrepo "$r" inner)"
git -C "$d" config alias.qc '!git commit -F - --cleanup=verbatim'
git -C "$d" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
touch "$(git -C "$d" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "! alias through a wrapper chdir sees the moved-to sequencer" "$r" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 0

r2="$(newrepo "$TICKET")"
d2="$(subrepo "$r2" inner)"
git -C "$d2" config alias.qc '!git commit -F - --cleanup=verbatim'
run "! alias through a wrapper chdir, no sequencer: still gated" "$r2" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "! alias through a wrapper chdir, conforming subject allowed" "$r2" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

r="$(newrepo "$TICKET")"
d="$(subrepo "$r" inner)"
git -C "$d" config alias.qc commit
git -C "$d" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
touch "$(git -C "$d" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "git -C inner <alias>: sequencer in moved-to repo is exempt (#2166)" "$r" \
  $'git -C inner qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 0
r5="$(newrepo "$TICKET")"
d5="$(subrepo "$r5" inner)"
git -C "$d5" config alias.qc commit
run "git -C inner <alias>, no sequencer: still content-gated (#2166)" "$r5" \
  $'git -C inner qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2

r="$(newrepo "$TICKET")"
json=$(jq -n --arg c "$BAD_COMMIT" --arg d "$r" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
CLAUDE_PROJECT_DIR="$r" CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED=false \
  bash "$HOOK" <<<"$json" >/dev/null 2>&1
assert_exit "kill switch off: violating subject allowed" 0 $?

cache_run() {
  guard_invoke --command "$3" --cwd "$1" \
    -- "CLAUDE_PROJECT_DIR=$1" "CLAUDE_PLUGIN_DATA=$2"
  CACHE_RC=$GUARD_RC
}

VIOLATING=$'git commit -F - <<\'EOF\'\nnot a ticket subject\nEOF\n'
CONFORMING=$'git commit -F - <<\'EOF\'\nABC-1: a conforming subject\nEOF\n'

r="$(newrepo "$TICKET")"
pd="$TEST_TMPDIR/pdata-cache"
rm -rf "$pd"

cache_run "$r" "$pd" "$VIOLATING"
assert_exit "cache: cold run blocks a violating subject" 2 "$CACHE_RC"
CACHE_FILE="$(find "$pd/convention-pattern" -type f 2>/dev/null | head -1)"
if [[ -n "$CACHE_FILE" ]]; then ok "cache: cold run wrote a cache entry"; else bad "cache: no cache entry written"; fi
cache_run "$r" "$pd" "$VIOLATING"
assert_exit "cache: warm run blocks the same subject" 2 "$CACHE_RC"
cache_run "$r" "$pd" "$CONFORMING"
assert_exit "cache: warm run allows a conforming subject" 0 "$CACHE_RC"

CACHED_SUBJECT="$(sed -n '2p' "$CACHE_FILE")"
CACHED_TITLE="$(sed -n '3p' "$CACHE_FILE")"
FORKED_SUBJECT="$(bash "$HOOK_DIR/resolve-convention-pattern.sh" "$r" subject_pattern 2>/dev/null)"
FORKED_TITLE="$(bash "$HOOK_DIR/resolve-convention-pattern.sh" "$r" pr_title_pattern 2>/dev/null)"
assert_eq "cache: cached subject pattern equals the forked form" "$FORKED_SUBJECT" "$CACHED_SUBJECT"
assert_eq "cache: cached title pattern equals the forked form" "$FORKED_TITLE" "$CACHED_TITLE"
assert_eq "cache: entry records its repo root" \
  "$(git -C "$r" rev-parse --show-toplevel | tr -d '\r')" "$(sed -n '1p' "$CACHE_FILE")"
assert_eq "cache: entry carries its terminator" "END" "$(tail -n 1 "$CACHE_FILE")"
assert_contains "cache: entry records the team file as present" "$(cat "$CACHE_FILE")" \
  "DEP 1 $(git -C "$r" rev-parse --show-toplevel | tr -d '\r')/docs/conventions/source-control.yaml"
assert_contains "cache: entry records the absent well-known file" "$(cat "$CACHE_FILE")" \
  "DEP 0 $(git -C "$r" rev-parse --show-toplevel | tr -d '\r')/docs/conventions/source-control/commit-convention.yml"
assert_absent "cache: entry records no retired markdown file" "$(cat "$CACHE_FILE")" \
  "/.claude/source-control.md"
assert_contains "cache: entry records the absent personal file" "$(cat "$CACHE_FILE")" \
  "DEP 0 $(git -C "$r" rev-parse --show-toplevel | tr -d '\r')/docs/conventions/source-control.local.yaml"

CB_DIR="$TEST_TMPDIR/bash-shim"
mkdir -p "$CB_DIR"
CB_LOG="$TEST_TMPDIR/resolver-forks"
REAL_BASH="$(command -v bash)"
{
  printf '#!%s\n' "$REAL_BASH"
  printf 'case "$*" in *resolve-convention-pattern.sh*) printf "x\\n" >>"%s" ;; esac\n' "$CB_LOG"
  printf 'exec "%s" "$@"\n' "$REAL_BASH"
} >"$CB_DIR/bash"
chmod +x "$CB_DIR/bash"

: >"$CB_LOG"
json=$(jq -n --arg c "$VIOLATING" --arg d "$r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
CLAUDE_PROJECT_DIR="$r" CLAUDE_PLUGIN_DATA="$pd" PATH="$CB_DIR:$PATH" \
  bash "$HOOK" <<<"$json" >/dev/null 2>&1
assert_eq "cache: a warm run forks the resolver zero times" 0 "$(wc -l <"$CB_LOG" | tr -d ' ')"

printf '%s\n' "$CC" >"$r/docs/conventions/source-control.yaml"
touch -d '+1 minute' "$r/docs/conventions/source-control.yaml"
: >"$CB_LOG"
CONV_SUBJECT=$'git commit -F - <<\'EOF\'\nfeat: a conventional-commits subject\nEOF\n'
json=$(jq -n --arg c "$CONV_SUBJECT" --arg d "$r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
inval_rc=0
CLAUDE_PROJECT_DIR="$r" CLAUDE_PLUGIN_DATA="$pd" PATH="$CB_DIR:$PATH" \
  bash "$HOOK" <<<"$json" >/dev/null 2>&1 || inval_rc=$?
assert_exit "cache: after an mtime change the NEW pattern is enforced" 0 "$inval_rc"
if (($(wc -l <"$CB_LOG" | tr -d ' ') > 0)); then
  ok "cache: an mtime change re-forks the resolver"
else
  bad "cache: stale entry served after the convention file changed"
fi
cache_run "$r" "$pd" "$CONFORMING"
assert_exit "cache: the superseded pattern is no longer enforced" 2 "$CACHE_RC"
assert_contains "cache: entry now holds the new pattern" "$(sed -n '2p' "$CACHE_FILE")" "feat|fix"

r2="$(newrepo "$TICKET")"
json=$(jq -n --arg c "$VIOLATING" --arg d "$r2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
nodata_rc=0
CLAUDE_PROJECT_DIR="$r2" env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"$json" >/dev/null 2>&1 ||
  nodata_rc=$?
assert_exit "cache: unset plugin data still blocks a violating subject" 2 "$nodata_rc"

r3="$(newrepo "$TICKET")"
pd3="$TEST_TMPDIR/pdata-trunc"
rm -rf "$pd3"
cache_run "$r3" "$pd3" "$VIOLATING"
TRUNC_FILE="$(find "$pd3/convention-pattern" -type f 2>/dev/null | head -1)"
printf '%s\n' "$r3" >"$TRUNC_FILE"
touch -d '+1 minute' "$TRUNC_FILE"
cache_run "$r3" "$pd3" "$VIOLATING"
assert_exit "cache: a truncated entry re-resolves rather than disabling the gate" 2 "$CACHE_RC"

r4="$(newrepo "$TICKET")"
pd4="$TEST_TMPDIR/pdata-gone"
rm -rf "$pd4"
cache_run "$r4" "$pd4" "$VIOLATING"
assert_exit "cache: warmed while the team file exists (blocks)" 2 "$CACHE_RC"
rm -f "$r4/docs/conventions/source-control.yaml"
: >"$CB_LOG"
json=$(jq -n --arg c "$VIOLATING" --arg d "$r4" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
gone_rc=0
CLAUDE_PROJECT_DIR="$r4" CLAUDE_PLUGIN_DATA="$pd4" PATH="$CB_DIR:$PATH" \
  bash "$HOOK" <<<"$json" >/dev/null 2>&1 || gone_rc=$?
assert_exit "cache: team file deleted -> the removed policy is no longer enforced" 0 "$gone_rc"
if (($(wc -l <"$CB_LOG" | tr -d ' ') > 0)); then
  ok "cache: a deleted dependency re-forks the resolver"
else
  bad "cache: stale entry served after the team file was deleted"
fi

r5="$(newrepo "")"
pd5="$TEST_TMPDIR/pdata-appear"
rm -rf "$pd5"
cache_run "$r5" "$pd5" "$CONFORMING"
assert_exit "cache: warmed with no pattern (ticket subject allowed)" 0 "$CACHE_RC"
mkdir -p "$r5/docs/conventions/source-control"
printf 'subject_pattern: "^(feat|fix): .+"\n' >"$r5/docs/conventions/source-control/commit-convention.yml"
touch -d '1 minute ago' "$r5/docs/conventions/source-control/commit-convention.yml"
git -C "$r5" add docs/conventions/source-control/commit-convention.yml
: >"$CB_LOG"
json=$(jq -n --arg c "$CONFORMING" --arg d "$r5" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
appear_rc=0
CLAUDE_PROJECT_DIR="$r5" CLAUDE_PLUGIN_DATA="$pd5" PATH="$CB_DIR:$PATH" \
  bash "$HOOK" <<<"$json" >/dev/null 2>&1 || appear_rc=$?
assert_exit "cache: well-known YAML appeared -> its pattern now governs (ticket subject blocked)" 2 "$appear_rc"
if (($(wc -l <"$CB_LOG" | tr -d ' ') > 0)); then
  ok "cache: an appearing dependency re-forks the resolver"
else
  bad "cache: stale entry served after a higher-precedence file appeared"
fi
cache_run "$r5" "$pd5" "$CONV_SUBJECT"
assert_exit "cache: the appeared YAML's pattern is what is served warm" 0 "$CACHE_RC"

r6="$(newrepo "")"
addfolder "$r6" "$TICKET"
pd6="$TEST_TMPDIR/pdata-team-yaml"
rm -rf "$pd6"
cache_run "$r6" "$pd6" "$CONFORMING"
assert_exit "cache: warmed with the folder-form pattern before the team yaml exists" 0 "$CACHE_RC"
mkdir -p "$r6/docs/conventions"
printf 'subject_pattern: "^(feat|fix): .+"\n' >"$r6/docs/conventions/source-control.yaml"
touch -d '1 minute ago' "$r6/docs/conventions/source-control.yaml"
git -C "$r6" add docs/conventions/source-control.yaml
cache_run "$r6" "$pd6" "$CONFORMING"
assert_exit "cache: team yaml appeared -> its pattern now governs (ticket subject blocked)" 2 "$CACHE_RC"
cache_run "$r6" "$pd6" "$CONV_SUBJECT"
assert_exit "cache: the team yaml's pattern is what is served warm" 0 "$CACHE_RC"

r7="$(newrepo "")"
pd7="$TEST_TMPDIR/pdata-personal"
rm -rf "$pd7"
cache_run "$r7" "$pd7" "$VIOLATING"
assert_exit "cache: warmed with no pattern anywhere (violating subject allowed)" 0 "$CACHE_RC"
git -C "$r7" config core.excludesFile "$TEST_TMPDIR/no-global-excludes"
printf '%s\n' 'docs/conventions/**/*.local.*' >"$r7/.gitignore"
mkdir -p "$r7/docs/conventions"
printf '%s\n' "subject_pattern: '^[A-Z]+-[0-9]+: .+'" >"$r7/docs/conventions/source-control.local.yaml"
touch -d '1 minute ago' "$r7/docs/conventions/source-control.local.yaml"
cache_run "$r7" "$pd7" "$VIOLATING"
assert_exit "cache: personal file appeared -> its pattern now governs (violating subject blocked)" 2 "$CACHE_RC"

STUB_HOOKS="$TEST_TMPDIR/stub-hooks"
mkdir -p "$STUB_HOOKS"
cp "$HOOK_DIR"/*.sh "$STUB_HOOKS/"
cat >"$STUB_HOOKS/resolve-convention-pattern.sh" <<'EOF'
#!/usr/bin/env bash
# STUB_OK_KEY: that key resolves to STUB_OK_OUT; the other key fails as configured.
if [[ -n "${STUB_OK_KEY:-}" && "${2:-}" == "$STUB_OK_KEY" ]]; then
  printf '%s\n' "$STUB_OK_OUT"
  exit 0
fi
[[ -n "${STUB_ERR:-}" ]] && printf '%s\n' "$STUB_ERR" >&2
[[ -n "${STUB_OUT:-}" ]] && printf '%s\n' "$STUB_OUT"
exit "${STUB_RC:-0}"
EOF
STUB_HOOK="$STUB_HOOKS/block-convention-violation.sh"

stub_run() {
  local repo="$1" rc="$2" err="$3" out="$4" cmd="$5"
  shift 5
  guard_invoke --hook "$STUB_HOOK" --command "$cmd" --cwd "$repo" "$@" \
    -- "CLAUDE_PROJECT_DIR=$repo" "STUB_RC=$rc" "STUB_ERR=$err" "STUB_OUT=$out"
}

assert_notice() {
  local sys ctx check="${3:-commit-subject} convention check did not run"
  sys="$(jq -rs 'if length == 1 then .[0].systemMessage // "" else "" end' <<<"$GUARD_OUT")"
  ctx="$(jq -rs 'if length == 1 then .[0].hookSpecificOutput.additionalContext // "" else "" end' <<<"$GUARD_OUT")"
  assert_contains "$1: user channel names the check that did not run" "$sys" "$check"
  assert_contains "$1: user channel carries the diagnostic" "$sys" "$2"
  assert_contains "$1: model channel names the check that did not run" "$ctx" "$check"
  assert_contains "$1: model channel carries the diagnostic" "$ctx" "$2"
}

r="$(newrepo "$TICKET")"
stub_run "$r" 1 "" "" "$BAD_COMMIT"
assert_exit "resolver exit 1, empty stderr: allowed" 0 "$GUARD_RC"
assert_eq "resolver exit 1, empty stderr: no notice" "" "$GUARD_OUT"

stub_run "$r" 1 "resolve-convention-pattern: subject_pattern is not POSIX ERE" "" "$BAD_COMMIT"
assert_exit "resolver exit 1 with stderr: the call goes through" 0 "$GUARD_RC"
assert_notice "resolver exit 1 with stderr" "subject_pattern is not POSIX ERE"

stub_run "$r" 2 "resolve-convention-pattern: usage: bad key" "" "$BAD_COMMIT"
assert_exit "resolver exit 2: the call goes through" 0 "$GUARD_RC"
assert_notice "resolver exit 2" "usage: bad key"

stub_run "$r" 2 "" "" "$BAD_COMMIT"
assert_exit "resolver exit 2, no stderr: the call goes through" 0 "$GUARD_RC"
assert_notice "resolver exit 2, no stderr" "exit status 2"

stub_run "$r" 1 "resolve-convention-pattern: broken pointer" "" "gh pr create --title 'junk title'"
assert_exit "resolver failure on gh pr create --title: the call goes through" 0 "$GUARD_RC"
assert_notice "resolver failure on gh pr create --title" "broken pointer" PR-title

stub_run "$r" 1 "resolve-convention-pattern: broken pointer" "" "$BAD_COMMIT" --via dispatched
assert_exit "resolver failure under the dispatcher: the call goes through" 0 "$GUARD_RC"
assert_notice "resolver failure under the dispatcher" "broken pointer"

title_fails=(-- "CLAUDE_PROJECT_DIR=$r" STUB_RC=1 "STUB_ERR=resolve-convention-pattern: bad title"
  STUB_OUT= STUB_OK_KEY=subject_pattern "STUB_OK_OUT=^[A-Z]+-[0-9]+: .+")
guard_invoke --hook "$STUB_HOOK" --command "$BAD_COMMIT" --cwd "$r" "${title_fails[@]}"
assert_exit "title fails, subject resolves: a violating subject is still blocked" 2 "$GUARD_RC"
guard_invoke --hook "$STUB_HOOK" --command "$GOOD_COMMIT" --cwd "$r" "${title_fails[@]}"
assert_exit "title fails, subject resolves: a conforming subject is allowed" 0 "$GUARD_RC"
assert_eq "title fails, subject resolves: a commit carries no title notice" "" "$GUARD_OUT"
guard_invoke --hook "$STUB_HOOK" --command "gh pr create --title 'junk title'" --cwd "$r" "${title_fails[@]}"
assert_exit "title fails, subject resolves: gh pr create --title goes through" 0 "$GUARD_RC"
assert_notice "title fails, subject resolves: gh pr create --title" "bad title" PR-title

subject_fails=(-- "CLAUDE_PROJECT_DIR=$r" STUB_RC=1 "STUB_ERR=resolve-convention-pattern: bad subject"
  STUB_OUT= STUB_OK_KEY=pr_title_pattern "STUB_OK_OUT=^[A-Z]+-[0-9]+: .+")
guard_invoke --hook "$STUB_HOOK" --command "gh pr create --title 'junk title'" --cwd "$r" "${subject_fails[@]}"
assert_exit "subject fails, title resolves: a violating title is still blocked" 2 "$GUARD_RC"
guard_invoke --hook "$STUB_HOOK" --command "$BAD_COMMIT" --cwd "$r" "${subject_fails[@]}"
assert_exit "subject fails, title resolves: the commit goes through" 0 "$GUARD_RC"
assert_notice "subject fails, title resolves: commit" "bad subject"

stub_run "$r" 0 "" "^[A-Z]+-[0-9]+: .+" "$BAD_COMMIT"
assert_exit "stub resolver exit 0: a violating subject is still blocked" 2 "$GUARD_RC"
stub_run "$r" 0 "" "^[A-Z]+-[0-9]+: .+" "$GOOD_COMMIT"
assert_exit "stub resolver exit 0: a conforming subject is allowed" 0 "$GUARD_RC"
assert_eq "stub resolver exit 0: no notice" "" "$GUARD_OUT"

pdn="$TEST_TMPDIR/pdata-notice"
rm -rf "$pdn"
payload="$(jq -n --arg c "$BAD_COMMIT" --arg d "$r" \
  '{session_id:"conv-notice",tool_name:"Bash",tool_input:{command:$c},cwd:$d}')"
guard_invoke --hook "$STUB_HOOK" --payload "$payload" \
  -- "CLAUDE_PROJECT_DIR=$r" "CLAUDE_PLUGIN_DATA=$pdn" STUB_RC=1 "STUB_ERR=resolve-convention-pattern: broken pointer" STUB_OUT=
assert_notice "latch: first failure in a session" "broken pointer"
guard_invoke --hook "$STUB_HOOK" --payload "$payload" \
  -- "CLAUDE_PROJECT_DIR=$r" "CLAUDE_PLUGIN_DATA=$pdn" STUB_RC=1 "STUB_ERR=resolve-convention-pattern: broken pointer" STUB_OUT=
assert_exit "latch: the second failure still goes through" 0 "$GUARD_RC"
assert_eq "latch: the second failure in a session is quiet" "" "$GUARD_OUT"
assert_eq "a resolver failure writes no cache entry" "" \
  "$(find "$pdn/convention-pattern" -type f 2>/dev/null | head -1)"

pdx="$TEST_TMPDIR/pdata-notice-cross"
rm -rf "$pdx"
fail_env=(-- "CLAUDE_PROJECT_DIR=$r" "CLAUDE_PLUGIN_DATA=$pdx" STUB_RC=1
  "STUB_ERR=resolve-convention-pattern: broken pointer" STUB_OUT=)
guard_invoke --hook "$STUB_HOOK" --payload "$(jq -n --arg c "gh pr create --title 'junk title'" --arg d "$r" \
  '{session_id:"conv-notice-cross",tool_name:"Bash",tool_input:{command:$c},cwd:$d}')" "${fail_env[@]}"
assert_notice "latch per check: the PR-title failure" "broken pointer" PR-title
guard_invoke --hook "$STUB_HOOK" --payload "$(jq -n --arg c "$BAD_COMMIT" --arg d "$r" \
  '{session_id:"conv-notice-cross",tool_name:"Bash",tool_input:{command:$c},cwd:$d}')" "${fail_env[@]}"
assert_notice "latch per check: a later commit-subject failure still notices" "broken pointer"

stub_run "$r" 1 "resolve-convention-pattern: broken pointer" "" "gh pr create --web"
assert_exit "title resolver fails, gh pr create --web: the call goes through" 0 "$GUARD_RC"
assert_eq "title resolver fails, gh pr create --web: no notice" "" "$GUARD_OUT"

r="$(newrepo "$TICKET")"
nul_rc=0
CLAUDE_PROJECT_DIR="$r" bash "$HOOK" <<<"$(jq -n --arg d "$r" \
  '{tool_name:"Bash",tool_input:{command:("git status" + ([0]|implode))},cwd:$d}')" >/dev/null 2>&1 || nul_rc=$?
assert_exit "NUL in command (blocked)" 2 "$nul_rc"

STRACE_OK=0
if command -v strace >/dev/null 2>&1 && strace -f -qq -o /dev/null -e trace=execve true >/dev/null 2>&1; then
  STRACE_OK=1
fi
if ((STRACE_OK == 0)); then
  echo "skip: strace is unavailable or not permitted here, so the process-creation budget is UNVERIFIED in this run"
else
  trace_sites() { # <trace log> -> "<label> <yes|NO>" per external command
    awk '
      { pid = $1 }
      (/clone\(|clone3\(|vfork\(|[^e]fork\(/ || /clone resumed|fork resumed/) && / = [0-9]+$/ {
        n = split($0, a, " = "); child = a[n]
        if (child ~ /^[0-9]+$/) { parent[child] = pid; kids[pid]++ }
      }
      /execve\(/ {
        execed[pid] = 1
        line[pid] = $0
      }
      END {
        for (p in line) {
          l = line[p]
          lab = ""
          if (l ~ /resolve-convention-pattern\.sh/) lab = "resolver"
          else if (l ~ /"rev-parse", "--absolute-git-dir"/) lab = "sequencer-probe"
          else if (l ~ /"config", "--get", "alias\./) lab = "alias-probe"
          else if (l ~ /"mktemp"/) lab = "mktemp"
          if (lab == "") continue
          q = (p in parent) ? parent[p] : "-"
          printf "%s %s %s\n", lab, (q in execed ? "yes" : "NO"), (q == "-" ? 0 : kids[q]+0)
        }
      }
    ' "$1" | sort
  }
  trace_run() {
    local repo="$2" pdata="$3" cmd="$4" json
    TRACE_LOG="$TEST_TMPDIR/strace-$1.log"
    json=$(jq -n --arg c "$cmd" --arg d "$repo" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
    CLAUDE_PROJECT_DIR="$repo" CLAUDE_PLUGIN_DATA="$pdata" HOOK_TELEMETRY_SINK="" \
      strace -f -qq -s 512 -o "$TRACE_LOG" -e trace=clone,clone3,fork,vfork,execve \
      bash "$HOOK" <<<"$json" >/dev/null 2>/dev/null
    return 0
  }
  assert_site() {
    local site="$1" rows="$2" seen extra
    seen=$(printf '%s\n' "$rows" | grep -c "^$site " || true)
    if ((seen == 0)); then
      bad "budget: $site never ran in the traced scenario, so its budget is untested"
      return
    fi
    extra=$(printf '%s\n' "$rows" | grep "^$site " | grep -cv ' yes ' || true)
    if ((extra == 0)); then
      ok "budget: $site execs in the substitution's own subshell ($seen call(s), no extra fork)"
    else
      bad "budget: $site pays an extra fork in $extra of $seen call(s) — the redirect is back inside the substitution"
    fi
  }

  rt="$(newrepo "$TICKET")"
  rt_data="$TEST_TMPDIR/pdata-budget"
  rm -rf "$rt_data"
  trace_run commit "$rt" "$rt_data" "$GOOD_COMMIT"
  BUDGET_ROWS="$(trace_sites "$TRACE_LOG")"
  assert_site resolver "$BUDGET_ROWS"
  assert_site mktemp "$BUDGET_ROWS"
  assert_site sequencer-probe "$BUDGET_ROWS"

  trace_run alias "$rt" "$rt_data" "git wibble --dry-run"
  BUDGET_ROWS="$(trace_sites "$TRACE_LOG")"
  assert_site alias-probe "$BUDGET_ROWS"
fi

rd="$(newrepo "$TICKET")"
expect_both "dispatched parity: violating subject blocked" 2 \
  --command "$BAD_COMMIT" --cwd "$rd" -- "CLAUDE_PROJECT_DIR=$rd"
expect_both "dispatched parity: conforming subject allowed" 0 \
  --command "$GOOD_COMMIT" --cwd "$rd" -- "CLAUDE_PROJECT_DIR=$rd"
expect_both "dispatched parity: git status is not a commit" 0 \
  --command "git status --short" --cwd "$rd" -- "CLAUDE_PROJECT_DIR=$rd"
rn="$(newrepo "")"
expect_both "dispatched parity: no team file, no enforcement" 0 \
  --command "$BAD_COMMIT" --cwd "$rn" -- "CLAUDE_PROJECT_DIR=$rn"

report
