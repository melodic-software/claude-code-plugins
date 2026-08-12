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

# --- NUL in payload must fail closed (#2136) ----------------------------------
r="$(newrepo "$TICKET")"
nul_rc=0
CLAUDE_PROJECT_DIR="$r" bash "$HOOK" <<<"$(jq -n --arg d "$r" \
  '{tool_name:"Bash",tool_input:{command:("git status" + ([0]|implode))},cwd:$d}')" >/dev/null 2>&1 || nul_rc=$?
assert_exit "NUL in command (blocked)" 2 "$nul_rc"

report
