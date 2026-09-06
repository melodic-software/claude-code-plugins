#!/usr/bin/env bash
# Contract test for block-convention-violation.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse JSON on stdin,
# asserts on exit code (2 = blocked, 0 = allowed). Each case runs against an
# isolated repo root whose team convention file this test controls.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-convention-violation.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Isolated repo root with an optional team convention body. A real git repo so
# repo-root resolution and the sequencer probe answer for THIS directory, not
# the enclosing marketplace repo.
newrepo() {
  local d
  d="$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")"
  git -C "$d" init -q -b main
  mkdir -p "$d/.claude"
  [[ -n "${1:-}" ]] && printf '%s\n' "$1" >"$d/.claude/source-control.md"
  printf '%s' "$d"
}

# run <label> <repo> <command> <expected-exit> [tool]
run() {
  local label="$1" repo="$2" command="$3" expected="$4" tool="${5:-Bash}" rc json
  json=$(jq -n --arg t "$tool" --arg c "$command" --arg d "$repo" \
    '{tool_name:$t,tool_input:{command:$c},cwd:$d}')
  CLAUDE_PROJECT_DIR="$repo" bash "$HOOK" <<<"$json" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

TICKET=$'## subject_pattern\n^[A-Z]+-[0-9]+: .+\n\n## pr_title_pattern\nSame as `subject_pattern`.'
CC=$'## subject_pattern\nConventional Commits'
PCRE=$'## subject_pattern\n^(?:feat|fix): .+'

GOOD_COMMIT=$'git commit -F - --cleanup=verbatim <<\'EOF\'\nABC-123: do the thing\n\nBody line.\nEOF'
BAD_COMMIT=$'git commit -F - --cleanup=verbatim <<\'EOF\'\njunk subject\n\nBody line.\nEOF'

# --- unresolved -> no enforcement ---------------------------------------------
r="$(newrepo "")"
run "no team file: violating subject allowed" "$r" "$BAD_COMMIT" 0
r="$(newrepo $'## trailer_policy\nnone')"
run "key absent: violating subject allowed" "$r" "$BAD_COMMIT" 0
r="$(newrepo "$PCRE")"
run "PCRE pattern: non-enforceable, allowed" "$r" "$BAD_COMMIT" 0

# --- subject enforcement -------------------------------------------------------
r="$(newrepo "$TICKET")"
run "ticket pattern: conforming subject allowed" "$r" "$GOOD_COMMIT" 0
run "ticket pattern: violating subject blocked" "$r" "$BAD_COMMIT" 2
run "ticket pattern: violating subject in prose (no commit) allowed" "$r" "echo 'junk subject'" 0
run "ticket pattern: git status is not a commit, allowed" "$r" "git status --short" 0

# Benign commands must not spawn git: repo_root and alias.<builtin> used to run
# on every Bash call. Counted through a PATH shim; function-level forks are
# invisible to it, matching spawn-census.sh.
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

# --- exemption taxonomy (inherited from block-noncanonical-commit) ------------
r="$(newrepo "$TICKET")"
run "--amend exempt" "$r" "git commit --amend --no-edit" 0
run "-C exempt" "$r" "git commit -C HEAD~1" 0
run "--fixup exempt" "$r" "git commit --fixup abc123" 0
run "-F path exempt (message not on command line)" "$r" "git commit -F msg.txt" 0
run "-m form not stdin-form (mechanic gate's concern), allowed here" "$r" \
  "git commit -m 'junk subject'" 0

# --- sequencer in progress: never content-gated -------------------------------
r="$(newrepo "$TICKET")"
git -C "$r" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
mkdir -p "$(git -C "$r" rev-parse --absolute-git-dir)"
touch "$(git -C "$r" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "sequencer: violating subject allowed mid-merge" "$r" "$BAD_COMMIT" 0

# --- non-heredoc stdin producer: content unknown, skip ------------------------
r="$(newrepo "$TICKET")"
run "printf | git commit -F -: unreadable content, allowed" "$r" \
  "printf 'junk subject' | git commit -F -" 0

# --- gh pr create --title ------------------------------------------------------
r="$(newrepo "$TICKET")"
run "gh pr create: conforming --title allowed" "$r" \
  "gh pr create --title 'ABC-9: ship it' --body-file b.md" 0
run "gh pr create: violating --title blocked" "$r" \
  "gh pr create --title 'junk title' --body-file b.md" 2
run "gh pr create: violating --title= blocked" "$r" \
  "gh pr create --title='junk title'" 2
run "gh pr create: no --title never blocked" "$r" "gh pr create --web" 0
run "gh pr edit --title out of scope, allowed" "$r" "gh pr edit 12 --title 'junk'" 0
r="$(newrepo $'## subject_pattern\n^[A-Z]+-[0-9]+: .+')"
run "no pr_title_pattern key: title not gated" "$r" "gh pr create --title 'junk'" 0

# --- PowerShell canonical here-string form ------------------------------------
r="$(newrepo "$TICKET")"
PS_GOOD=$'@\'\nABC-77: powershell subject\n\'@ | git commit -F - --cleanup=verbatim'
PS_BAD=$'@\'\njunk subject\n\'@ | git commit -F - --cleanup=verbatim'
run "PS: conforming here-string subject allowed" "$r" "$PS_GOOD" 0 PowerShell
run "PS: violating here-string subject blocked" "$r" "$PS_BAD" 2 PowerShell
run "PS: violating gh pr create --title blocked" "$r" \
  "gh pr create --title 'junk title'" 2 PowerShell

# --- review round 1: raw subject, env-prefixed gh, alias-expanded commit ------
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
# Deprecated builtins can be aliased (git-config; git.c DEPRECATED bit).
# `whatchanged` must keep probing so `alias.whatchanged = commit` cannot skip
# the subject gate on a git that honors the exception.
r="$(newrepo "$TICKET")"
git -C "$r" config alias.whatchanged commit
run "deprecated builtin alias.whatchanged: violating subject blocked" "$r" \
  $'git whatchanged -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "deprecated builtin alias.whatchanged: conforming subject allowed" "$r" \
  $'git whatchanged -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0
# Names added after git 2.25 can still be aliases on an older git
# (`bugreport` landed in 2.27). Probe them.
r="$(newrepo "$TICKET")"
git -C "$r" config alias.bugreport commit
run "post-2.25 name alias.bugreport: violating subject blocked" "$r" \
  $'git bugreport -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "post-2.25 name alias.bugreport: conforming subject allowed" "$r" \
  $'git bugreport -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

# --- effective_dir is git's own slice, plus the wrapper's replayed chdir -------
# The alias lookup is the reachable consumer: it has no stdin-form gate and no
# exemption gate, and it fails OPEN — reading the wrong repository's config
# misses the expansion, so the guard never learns the subcommand is `commit`.
#
# `git commit -C HEAD` is deliberately NOT the control here. `-C` sets exempt=1
# and the hook returns before effective_dir is ever called, so that invocation
# answers "allowed" on both the old and the new code and would read as already
# fixed. The positional case is probed through the alias lookup instead.

# A real git repo nested at <parent>/<name>, with a team convention of its own.
subrepo() {
  local d="$1/$2"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  mkdir -p "$d/.claude"
  printf '%s\n' "$TICKET" >"$d/.claude/source-control.md"
  printf '%s' "$d"
}

# GNU env's `-u NAME` consumes the next word, so in `env -u -C git …` the `-C` is
# the variable to unset and git never moves. Scanning every word composed
# <cwd>/git and read that directory's aliases instead of the real repository's.
r="$(newrepo "$TICKET")"
git -C "$r" config alias.qc commit
run "env -u -C git <alias>: alias resolves in the TRUE repo (blocked)" "$r" \
  $'env -u -C git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "env -u -C git <alias>: conforming subject still allowed" "$r" \
  $'env -u -C git qc -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

# The mirror, flipping the other way: the alias exists ONLY in a real repository
# at <cwd>/git. Composing that directory blocked on an alias git would never
# expand; reading the true repository is correctly silent.
r="$(newrepo "$TICKET")"
d="$(subrepo "$r" git)"
git -C "$d" config alias.qc commit
run "env -u -C git <alias>: decoy repo at <cwd>/git is not read" "$r" \
  $'env -u -C git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 0

# A `-C` AFTER the subcommand is an argument, not a chdir. The alias ends in `--`
# so the trailing `-C dec` git appends to the expansion cannot re-trigger the
# reuse-message exemption in the recursed frame — without that, the case answers
# "allowed" on both trees for a reason unrelated to effective_dir.
r="$(newrepo "$TICKET")"
d="$(subrepo "$r" dec)"
git -C "$d" config alias.qs 'commit -F - --cleanup=verbatim --'
run "post-subcommand -C is not a chdir (decoy repo not read)" "$r" \
  $'git qs -C dec <<\'EOF\'\njunk subject\nEOF' 0

# A genuine wrapper chdir IS a relocation, and the slice cannot see it — so it is
# replayed from HOOK_GIT_RESOLVED_WRAPPER_DIRS, matching what #2100 established
# for block-dangerous-git. The alias lives only in the moved-to repository.
r="$(newrepo "$TICKET")"
d="$(subrepo "$r" inner)"
git -C "$d" config alias.qc commit
run "env -C <dir> git <alias>: wrapper chdir is replayed (blocked)" "$r" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "env -C <dir> git <alias>: conforming subject still allowed" "$r" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

# The `-C <dir>` spelling above answers 2 on BOTH trees — the old every-word scan
# catches that particular `-C inner` by accident — so it proves the replay is
# load-bearing only under mutation, not against the unfixed hook. `--chdir=` is
# the spelling that scan does NOT recognize (it matched the literal word `-C`
# only), so this one genuinely fails before the fix and passes after. Keep the
# `-C` case too: it is what catches a DOUBLE application of the replay, which
# composes `<cwd>/inner/inner` and drops to 0 — and keep its directory RELATIVE,
# because an absolute wrapper dir makes a double-apply idempotent and the guard
# silently evaporates.
run "env --chdir=<dir> git <alias>: attached long form is replayed" "$r" \
  $'env --chdir=inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2

# The OTHER effective_dir consumer: sequencer_in_progress. Every pre-existing
# `sequencer:` case probes the payload cwd's own repo with no wrapper at all, so
# nothing reached this call site through a wrapper chdir. `--chdir=` again, so the
# case discriminates rather than being caught by the old scan.
r3="$(newrepo "$TICKET")"
d3="$(subrepo "$r3" inner)"
git -C "$d3" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
touch "$(git -C "$d3" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "wrapper chdir reaches the sequencer probe (exempt mid-merge)" "$r3" \
  $'env --chdir=inner git commit -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 0
# Its discriminator: identical command, no MERGE_HEAD anywhere. Without this the
# case above passes for any reason that makes the commit unreachable.
r4="$(newrepo "$TICKET")"
subrepo "$r4" inner >/dev/null
run "wrapper chdir, no sequencer: still content-gated" "$r4" \
  $'env --chdir=inner git commit -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2

# --- a `!` shell alias must inherit the directory its invocation resolved to ---
# Review finding on #2152. A `!` alias body re-parses as a NEW top-level command,
# so its argv carries neither the wrapper that moved git nor git's own globals.
# The wrapper's chdir was therefore dropped on the way in, and the alias body's
# sequencer probe ran against the payload cwd: a prepared merge subject in the
# moved-to repository was BLOCKED where the guard documents an exemption.
#
# Every case here pairs with one that must answer differently, because "exempt"
# and "no sequencer" are indistinguishable if only the exempting case is asserted.
r="$(newrepo "$TICKET")"
d="$(subrepo "$r" inner)"
git -C "$d" config alias.qc '!git commit -F - --cleanup=verbatim'
git -C "$d" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
touch "$(git -C "$d" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "! alias through a wrapper chdir sees the moved-to sequencer" "$r" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 0

# The discriminator: same command, same wrapper, same `!` alias — no MERGE_HEAD.
# Without this, the case above passes for any reason that makes `!` aliases
# unreachable, which is exactly how a dead fixture reads as a green one.
r2="$(newrepo "$TICKET")"
d2="$(subrepo "$r2" inner)"
git -C "$d2" config alias.qc '!git commit -F - --cleanup=verbatim'
run "! alias through a wrapper chdir, no sequencer: still gated" "$r2" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\njunk subject\nEOF' 2
run "! alias through a wrapper chdir, conforming subject allowed" "$r2" \
  $'env -C inner git qc -F - --cleanup=verbatim <<\'EOF\'\nABC-5: fine\nEOF' 0

# --- plain git alias must forward git's own globals through the recursion (#2166) ---
# `git -C inner qc` (plain alias, not `!`) dropped `-C inner` at the alias hop:
# the slice stopped at gi, so git's globals between git and the subcommand never
# reached the recursed frame and the sequencer probe ran in the wrong repository.
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

# --- kill switch ---------------------------------------------------------------
r="$(newrepo "$TICKET")"
json=$(jq -n --arg c "$BAD_COMMIT" --arg d "$r" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
CLAUDE_PROJECT_DIR="$r" CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED=false \
  bash "$HOOK" <<<"$json" >/dev/null 2>&1
assert_exit "kill switch off: violating subject allowed" 0 $?

# --- resolved pattern cache ---------------------------------------------------
# The gate forks the resolver twice per call, on the first commit or
# `gh pr create` this process sees. The cache must answer with EXACTLY what the
# fork answered, must stop forking once warm, and must notice a convention change.

# cache_run <repo> <plugin-data> <command> -> exit code in $CACHE_RC
cache_run() {
  local json
  json=$(jq -n --arg c "$3" --arg d "$1" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
  CACHE_RC=0
  CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_DATA="$2" bash "$HOOK" <<<"$json" >/dev/null 2>&1 ||
    CACHE_RC=$?
}

VIOLATING=$'git commit -F - <<\'EOF\'\nnot a ticket subject\nEOF\n'
CONFORMING=$'git commit -F - <<\'EOF\'\nABC-1: a conforming subject\nEOF\n'

r="$(newrepo "$TICKET")"
pd="$TEST_TMPDIR/pdata-cache"
rm -rf "$pd"

# 1. Cold: the fork decides. Warm: the cache must decide the SAME way.
cache_run "$r" "$pd" "$VIOLATING"
assert_exit "cache: cold run blocks a violating subject" 2 "$CACHE_RC"
CACHE_FILE="$(find "$pd/convention-pattern" -type f 2>/dev/null | head -1)"
if [[ -n "$CACHE_FILE" ]]; then ok "cache: cold run wrote a cache entry"; else bad "cache: no cache entry written"; fi
cache_run "$r" "$pd" "$VIOLATING"
assert_exit "cache: warm run blocks the same subject" 2 "$CACHE_RC"
cache_run "$r" "$pd" "$CONFORMING"
assert_exit "cache: warm run allows a conforming subject" 0 "$CACHE_RC"

# 2. The cached pattern EQUALS what the fork produces. Compared value to value,
#    not decision to decision: two different patterns can agree on one subject.
CACHED_SUBJECT="$(sed -n '2p' "$CACHE_FILE")"
CACHED_TITLE="$(sed -n '3p' "$CACHE_FILE")"
FORKED_SUBJECT="$(bash "$HOOK_DIR/resolve-convention-pattern.sh" "$r" subject_pattern 2>/dev/null)"
FORKED_TITLE="$(bash "$HOOK_DIR/resolve-convention-pattern.sh" "$r" pr_title_pattern 2>/dev/null)"
assert_eq "cache: cached subject pattern equals the forked form" "$FORKED_SUBJECT" "$CACHED_SUBJECT"
assert_eq "cache: cached title pattern equals the forked form" "$FORKED_TITLE" "$CACHED_TITLE"
# The recorded root is git's own answer, which on Windows Git Bash is the
# drive-letter form and not the MSYS path the fixture was created under. What
# this case holds is that the entry names the root it was resolved for, so a
# sanitized filename collision between two roots cannot serve the wrong pattern.
assert_eq "cache: entry records its repo root" \
  "$(git -C "$r" rev-parse --show-toplevel | tr -d '\r')" "$(sed -n '1p' "$CACHE_FILE")"
assert_eq "cache: entry carries its terminator" "END" "$(tail -n 1 "$CACHE_FILE")"
# Every dependency the resolver reads is recorded with its existence at warm
# time, which is what lets a later deletion or appearance read as a miss.
assert_contains "cache: entry records the team file as present" "$(cat "$CACHE_FILE")" \
  "DEP 1 $(git -C "$r" rev-parse --show-toplevel | tr -d '\r')/.claude/source-control.md"
assert_contains "cache: entry records the absent well-known file" "$(cat "$CACHE_FILE")" \
  "DEP 0 $(git -C "$r" rev-parse --show-toplevel | tr -d '\r')/docs/conventions/source-control/commit-convention.yml"

# 3. A warm cache must not fork the resolver again. Counted through a shim ahead
#    of the real bash on PATH, so this measures the spawn the change removes.
CB_DIR="$TEST_TMPDIR/bash-shim"
mkdir -p "$CB_DIR"
CB_LOG="$TEST_TMPDIR/resolver-forks"
REAL_BASH="$(command -v bash)"
{
  # The shebang names the real interpreter by path. `#!/usr/bin/env bash` would
  # resolve `bash` through the PATH this shim is installed on and find the shim,
  # which never terminates.
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

# 4. An mtime change on the convention file invalidates. The new pattern must be
#    the one enforced, proven by a subject that the OLD pattern rejected and the
#    NEW one accepts. `touch -d` rather than a bare write: two writes inside one
#    filesystem timestamp tick would not move the mtime at all.
printf '%s\n' "$CC" >"$r/.claude/source-control.md"
touch -d '+1 minute' "$r/.claude/source-control.md"
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
# The old pattern is genuinely gone: a ticket subject no longer satisfies the
# gate, and the entry on disk now carries the Conventional Commits pattern.
cache_run "$r" "$pd" "$CONFORMING"
assert_exit "cache: the superseded pattern is no longer enforced" 2 "$CACHE_RC"
assert_contains "cache: entry now holds the new pattern" "$(sed -n '2p' "$CACHE_FILE")" "feat|fix"

# 5. No plugin data dir -> no caching, and the gate still decides correctly.
r2="$(newrepo "$TICKET")"
json=$(jq -n --arg c "$VIOLATING" --arg d "$r2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
nodata_rc=0
CLAUDE_PROJECT_DIR="$r2" env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"$json" >/dev/null 2>&1 ||
  nodata_rc=$?
assert_exit "cache: unset plugin data still blocks a violating subject" 2 "$nodata_rc"

# 6. A truncated entry is a miss, never a silent no-enforcement.
r3="$(newrepo "$TICKET")"
pd3="$TEST_TMPDIR/pdata-trunc"
rm -rf "$pd3"
cache_run "$r3" "$pd3" "$VIOLATING"
TRUNC_FILE="$(find "$pd3/convention-pattern" -type f 2>/dev/null | head -1)"
printf '%s\n' "$r3" >"$TRUNC_FILE"
touch -d '+1 minute' "$TRUNC_FILE"
cache_run "$r3" "$pd3" "$VIOLATING"
assert_exit "cache: a truncated entry re-resolves rather than disabling the gate" 2 "$CACHE_RC"

# 7. A dependency that DISAPPEARS invalidates. `[[ cache -nt missing ]]` is
#    true, so an mtime-only check would keep enforcing the deleted policy for
#    ever; the recorded existence is what turns the deletion into a miss. The
#    resolver now answers no enforcement, so the violating subject passes.
r4="$(newrepo "$TICKET")"
pd4="$TEST_TMPDIR/pdata-gone"
rm -rf "$pd4"
cache_run "$r4" "$pd4" "$VIOLATING"
assert_exit "cache: warmed while the team file exists (blocks)" 2 "$CACHE_RC"
rm -f "$r4/.claude/source-control.md"
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

# 8. A dependency that APPEARS invalidates, even with an mtime OLDER than the
#    cache (a restore from an archive, or `cp -p`), where `-nt` alone would
#    still read fresh. The tracked well-known YAML outranks the markdown H2, so
#    once it exists the pattern it carries is the one enforced.
r5="$(newrepo "$TICKET")"
pd5="$TEST_TMPDIR/pdata-appear"
rm -rf "$pd5"
cache_run "$r5" "$pd5" "$CONFORMING"
assert_exit "cache: warmed with the markdown pattern (ticket subject allowed)" 0 "$CACHE_RC"
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

# --- NUL in payload must fail closed (#2136) ----------------------------------
r="$(newrepo "$TICKET")"
nul_rc=0
CLAUDE_PROJECT_DIR="$r" bash "$HOOK" <<<"$(jq -n --arg d "$r" \
  '{tool_name:"Bash",tool_input:{command:("git status" + ([0]|implode))},cwd:$d}')" >/dev/null 2>&1 || nul_rc=$?
assert_exit "NUL in command (blocked)" 2 "$nul_rc"

# --- process-creation budget on this file's three external call sites ---------
# WHY A KERNEL TRACE AND NOT A PATH SHIM OR xtrace. The cost this asserts on is
# a fork that never execs, so neither of the counters this repo already uses can
# see it: a PATH shim (plugins/performance/scripts/spawn-census.sh) only fires
# when something is EXECUTED, and `bash -x` prints one line per command in
# command position whether that command cost one process or two. Only
# clone/execve from the kernel distinguishes them.
#
# THE MECHANIC. GNU Bash runs a command substitution in a forked subshell, and
# execs the body IN that subshell instead of forking a second time only when the
# body is a single command carrying NO REDIRECTION OF ITS OWN. So
# `v=$(cmd 2>/dev/null)` costs two process creations for one exec, while
# `{ v=$(cmd); } 2>/dev/null` costs one. On the Windows Git Bash hosts this
# marketplace targets a fork is a full process creation, which is the whole
# reason the difference is worth a test.
#
# THE ASSERTION is per call site, not a total, so it does not go stale when the
# synced `hook-utils.sh` or the vendored `resolve-convention-pattern.sh` change
# their own spawn shape (neither is this file's to fix, and both still show the
# wasted-fork signature in the same trace). For each external command THIS FILE
# starts, the process that execs it must have a parent that itself execve'd —
# that is, the exec landed in the substitution's own subshell. A parent that
# never execs and has exactly one child is the extra fork, and is a failure.
#
# NON-VACUITY is asserted, not assumed: each site must actually appear in the
# trace, so a scenario that stops reaching a site fails here rather than passing
# by absence.
STRACE_OK=0
if command -v strace >/dev/null 2>&1 && strace -f -qq -o /dev/null -e trace=execve true >/dev/null 2>&1; then
  STRACE_OK=1
fi
if ((STRACE_OK == 0)); then
  echo "skip: strace is unavailable or not permitted here, so the process-creation budget is UNVERIFIED in this run"
else
  # Parent map + exec set from one trace. `-s 512` matters: strace truncates
  # strings at 32 bytes by default, which would cut every argv this matches on.
  # `<unfinished ...>` / `<... clone resumed>` splits are handled by keying on
  # any clone/fork line that ends in the child pid.
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
          if (lab == "") continue
          q = (p in parent) ? parent[p] : "-"
          printf "%s %s %s\n", lab, (q in execed ? "yes" : "NO"), (q == "-" ? 0 : kids[q]+0)
        }
      }
    ' "$1" | sort
  }
  # trace_run <label> <repo> <plugin-data> <command> -> TRACE_LOG
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
  # assert_site <site label> <trace output> — every occurrence must be direct.
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

  # Cold cache + a stdin-form commit: both resolver forks and the sequencer probe.
  rt="$(newrepo "$TICKET")"
  rt_data="$TEST_TMPDIR/pdata-budget"
  rm -rf "$rt_data"
  trace_run commit "$rt" "$rt_data" "$GOOD_COMMIT"
  BUDGET_ROWS="$(trace_sites "$TRACE_LOG")"
  assert_site resolver "$BUDGET_ROWS"
  assert_site sequencer-probe "$BUDGET_ROWS"

  # A non-builtin subcommand is the alias probe's only trigger, and it is the
  # one of the three that sits on the per-tool-call path.
  trace_run alias "$rt" "$rt_data" "git wibble --dry-run"
  BUDGET_ROWS="$(trace_sites "$TRACE_LOG")"
  assert_site alias-probe "$BUDGET_ROWS"
fi

report
