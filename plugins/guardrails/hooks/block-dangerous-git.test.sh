#!/usr/bin/env bash
# Contract test for block-dangerous-git.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-dangerous-git.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# A lease expectation is judged against the hash width of the repository the
# push would run in, so every case that carries one needs a KNOWN working
# directory — the ambient one is whatever invoked the suite. Fixtures: a SHA-1
# repository (the default every `run` uses), a SHA-256 one, and a plain
# directory that is no repository at all.
REPO_SHA1="$TEST_TMPDIR/repo-sha1"
REPO_SHA256="$TEST_TMPDIR/repo-sha256"
NOT_A_REPO="$TEST_TMPDIR/not-a-repo"
mkdir -p "$REPO_SHA1" "$REPO_SHA256" "$NOT_A_REPO"
git init -q --object-format=sha1 "$REPO_SHA1" ||
  bad "fixture: could not create the SHA-1 repository"
# SHA-256 repositories are git 2.29+. A missing fixture is a hard failure rather
# than a skip: without it the wrong-width case below is untested, and a test
# that quietly does not run reads as coverage it is not.
git init -q --object-format=sha256 "$REPO_SHA256" ||
  bad "fixture: could not create the SHA-256 repository (git 2.29+ required)"

# A PreToolUse payload carries `cwd` — the directory the TOOL CALL runs in, which
# is not the hook process's own. The width probe is measured from it (#2124), so
# every case has to state it; the shared command_json builder omits the field.
command_json_cwd() {
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'
}

# run_in <dir> <label> <command> <expected-exit> [extra-env NAME=VAL ...]
# The payload cwd and the hook process's directory are BOTH <dir> here — the
# ordinary case, where they agree. run_split below is the divergent one.
#
# Setting the payload cwd is load-bearing even for the agreeing case: without it
# the guard falls to CLAUDE_PROJECT_DIR, which is exported in any session that
# runs this suite under Claude Code, and every fixture row would then be measured
# against the host repository instead of the fixture.
run_in() {
  local dir="$1" label="$2" command="$3" expected="$4"
  shift 4
  local rc
  (cd "$dir" && env "$@" bash "$HOOK" <<<"$(command_json_cwd "$command" "$dir")" >/dev/null 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# run_split <payload-cwd> <process-cwd> <label> <command> <expected-exit> [env ...]
# The two directories DIVERGE, which is the shape #2124 was reported in: the hook
# process sits at the session root while the tool call runs elsewhere.
run_split() {
  local pcwd="$1" proc="$2" label="$3" command="$4" expected="$5"
  shift 5
  local rc
  (cd "$proc" && env "$@" bash "$HOOK" <<<"$(command_json_cwd "$command" "$pcwd")" >/dev/null 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# run_nocwd <process-cwd> <label> <command> <expected-exit> [env ...]
# A payload carrying NO cwd field, for the lower rungs of the base chain.
run_nocwd() {
  local proc="$1" label="$2" command="$3" expected="$4"
  shift 4
  local rc
  (cd "$proc" && env "$@" bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# run <label> <command> <expected-exit> [extra-env NAME=VAL ...]
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  run_in "$REPO_SHA1" "$label" "$command" "$expected" "$@"
}

# --- push-force ---------------------------------------------------------------
run "git push --force (blocked)" "git push --force" 2
run "git push -f (blocked)" "git push -f origin main" 2
run "git push origin main --force (flag after operands, blocked)" "git push origin main --force" 2
run "git push -uf (bundled f, blocked)" "git push -uf origin main" 2
run "git push origin +HEAD:main (refspec force, blocked)" "git push origin +HEAD:main" 2
run "git push origin +feature (bare + refspec, blocked)" "git push origin +feature" 2
run "git push --mirror (force-updates all refs, blocked)" "git push --mirror backup" 2
run "git push --force-with-lease (no expected value, blocked)" "git push --force-with-lease" 2
run "git push --force-with-lease=main (refname only, no expectation, blocked)" "git push --force-with-lease=main origin main" 2
# An object id of THIS repository's hash width — the only expectation shape the
# guard accepts as immutable. Anything shorter is an abbreviation git resolves
# as a ref first; anything of the other width is an ordinary ref name here, so
# git resolves it too and the expectation moves with whatever it names.
SHA1_OID=0123456789abcdef0123456789abcdef01234567
SHA256_OID=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
run "git push --force-with-lease=main:<40-hex> (full object id, allowed)" "git push --force-with-lease=main:$SHA1_OID origin main" 0
run "git push --force-with-lease=main:<64-hex> in a SHA-1 repo (a 64-hex ref name resolves here, blocked)" "git push --force-with-lease=main:$SHA256_OID origin main" 2
run_in "$REPO_SHA256" "git push --force-with-lease=main:<64-hex> in a SHA-256 repo (full object id, allowed)" "git push --force-with-lease=main:$SHA256_OID origin main" 0
run_in "$REPO_SHA256" "git push --force-with-lease=main:<40-hex> in a SHA-256 repo (a 40-hex ref name resolves here, blocked)" "git push --force-with-lease=main:$SHA1_OID origin main" 2
run_in "$NOT_A_REPO" "git push --force-with-lease=main:<40-hex> outside a repository (width undeterminable, fail-closed block)" "git push --force-with-lease=main:$SHA1_OID origin main" 2

run_stderr_in() {
  local dir="$1" label="$2" command="$3" expected="$4"
  shift 4
  local rc err
  err="$(cd "$dir" && env "$@" bash "$HOOK" <<<"$(command_json_cwd "$command" "$dir")" 2>&1 >/dev/null)"
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  printf '%s' "$err"
}

err="$(run_stderr_in "$NOT_A_REPO" "width-undeterminable block names the git failure, not abbreviation" "git push --force-with-lease=main:$SHA1_OID origin main" 2)"
assert_contains "width-undeterminable: cites object format" "$err" "hash format could not be determined"
assert_absent "width-undeterminable: does not blame abbreviation" "$err" "abbreviated object id"
run_in "$NOT_A_REPO" "git push --force-with-lease=main: outside a repository (empty expect needs no width, allowed)" "git push --force-with-lease=main: origin main" 0
# git's repository-locating globals move the push off the invoking directory, so
# the width follows them. `-C` takes its value as a separate word — git rejects
# an attached `-C<path>` with its usage.
run "git -C <sha256-repo> push --force-with-lease=main:<40-hex> (40-hex is a name in the target, blocked)" "git -C $REPO_SHA256 push --force-with-lease=main:$SHA1_OID origin main" 2
run "git -C <sha256-repo> push --force-with-lease=main:<64-hex> (object id in the target, allowed)" "git -C $REPO_SHA256 push --force-with-lease=main:$SHA256_OID origin main" 0
run_in "$REPO_SHA256" "git -C <sha1-repo> push --force-with-lease=main:<64-hex> (64-hex is a name in the target, blocked)" "git -C $REPO_SHA1 push --force-with-lease=main:$SHA256_OID origin main" 2
run_in "$REPO_SHA256" "git -C <sha1-repo> push --force-with-lease=main:<40-hex> (object id in the target, allowed)" "git -C $REPO_SHA1 push --force-with-lease=main:$SHA1_OID origin main" 0
run "git --git-dir=<sha256-repo>/.git push --force-with-lease=main:<40-hex> (blocked)" "git --git-dir=$REPO_SHA256/.git push --force-with-lease=main:$SHA1_OID origin main" 2
run "git -C <not-a-repo> push --force-with-lease=main:<40-hex> (width undeterminable, fail-closed block)" "git -C $NOT_A_REPO push --force-with-lease=main:$SHA1_OID origin main" 2
run "git -c x=y -C <sha256-repo> push --force-with-lease=main:<64-hex> (config value skipped, not mistaken for a path, allowed)" "git -c x=y -C $REPO_SHA256 push --force-with-lease=main:$SHA256_OID origin main" 0

# A WRAPPER's chdir moves git just as git's own -C does, and the width probe must
# follow it. The locating-option walk is deliberately scoped to `[git, subcommand)`
# — it cannot know which wrapper options take a value — so the relocation reaches
# it only through hook::git_resolve_index, the one parser that can tell `env -C
# <dir>` (a real chdir) from the `-C` in `env -u -C git` (the operand of -u).
# Losing it probed the INVOKING directory, where a 40-hex lease reads as an object
# id while the push runs where it is a movable ref name.
run "env -C <sha256-repo> git push --force-with-lease=main:<40-hex> (40-hex is a name where git runs, blocked)" "env -C $REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main" 2
run "env -C <sha256-repo> git push --force-with-lease=main:<64-hex> (object id where git runs, allowed)" "env -C $REPO_SHA256 git push --force-with-lease=main:$SHA256_OID origin main" 0
run_in "$REPO_SHA256" "env -C <sha1-repo> git push --force-with-lease=main:<64-hex> (64-hex is a name where git runs, blocked)" "env -C $REPO_SHA1 git push --force-with-lease=main:$SHA256_OID origin main" 2
run "env --chdir=<sha256-repo> git push --force-with-lease=main:<40-hex> (long form, blocked)" "env --chdir=$REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main" 2
run "sudo -D <sha256-repo> git push --force-with-lease=main:<40-hex> (sudo's chdir, blocked)" "sudo -D $REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main" 2
# The mirror image: an option that only LOOKS like a chdir must not move the probe.
# GNU env's `-u NAME` consumes the next word, so the `-C` in `env -u -C git` is
# the variable name and git never moves — the lease is judged where it stands.
run "env -u -C git push --force-with-lease=main:<40-hex> (-C is -u's operand, no chdir, allowed)" "env -u -C git push --force-with-lease=main:$SHA1_OID origin main" 0
# A wrapper chdir composes AHEAD of git's own -C, in that order: env relocates
# before git starts, so a relative `-C` resolves against the wrapper's directory.
run "env -C <sha256-parent> git -C <basename> push --force-with-lease=main:<64-hex> (composed, allowed)" "env -C $TEST_TMPDIR git -C repo-sha256 push --force-with-lease=main:$SHA256_OID origin main" 0
run "env -C <sha256-parent> git -C <basename> push --force-with-lease=main:<40-hex> (composed, blocked)" "env -C $TEST_TMPDIR git -C repo-sha256 push --force-with-lease=main:$SHA1_OID origin main" 2

# --- the payload's cwd is the base every probe is measured from (#2124) --------
# Claude Code launches the hook from the session root and runs the Bash tool
# wherever the session stands, so the two directories differ routinely. Probing
# only the hook process's own measured a repository the push never touches: a
# payload cwd in the SHA-256 fixture with the hook process in the SHA-1 one read
# a 40-hex lease as an immutable object id while git resolves it as a movable REF
# NAME where the push actually runs. No wrapper and no `cd` were needed.
run_split "$REPO_SHA256" "$REPO_SHA1" "payload cwd is the SHA-256 repo while the hook process stands in the SHA-1 one (40-hex is a name where the push runs, blocked)" "git push --force-with-lease=main:$SHA1_OID origin main" 2
run_split "$REPO_SHA256" "$REPO_SHA256" "control: both directories are the SHA-256 repo (blocked, and the fixture discriminates)" "git push --force-with-lease=main:$SHA1_OID origin main" 2
# The OPPOSITE direction, so the change is not merely "block more": where the
# command really runs, a 40-hex word IS an object id, and blocking it would be a
# false positive bought with the fix.
run_split "$REPO_SHA1" "$REPO_SHA256" "payload cwd is the SHA-1 repo while the hook process stands in the SHA-256 one (40-hex is a real object id where the push runs, allowed)" "git push --force-with-lease=main:$SHA1_OID origin main" 0
run_split "$REPO_SHA1" "$REPO_SHA256" "payload cwd is the SHA-1 repo, 64-hex expectation (a name there, blocked)" "git push --force-with-lease=main:$SHA256_OID origin main" 2

# A `!` shell alias runs its body as a fresh command in the RELOCATED repository,
# and the reparse builds a new segment frame whose own locating options start
# empty. Without carrying the relocation forward as that reparse's base, the
# body's push is judged against the payload cwd while git runs it elsewhere —
# the same misprobe one recursion level down.
run_split "$REPO_SHA1" "$REPO_SHA1" "git -C <sha256-repo> -c alias.y='!git push --force-with-lease=main:<40-hex>' y (the body runs in the SHA-256 repo, blocked)" "git -C $REPO_SHA256 -c alias.y='!git push --force-with-lease=main:$SHA1_OID origin main' y" 2
run_split "$REPO_SHA256" "$REPO_SHA256" "git -C <sha1-repo> -c alias.y='!git push --force-with-lease=main:<40-hex>' y (the body runs in the SHA-1 repo, allowed)" "git -C $REPO_SHA1 -c alias.y='!git push --force-with-lease=main:$SHA1_OID origin main' y" 0
# #2151: an explicit --git-dir/--work-tree is inherited by a `!` body via GIT_DIR,
# not relocated like -C. Without replaying those globals into the reparse, a
# 40-hex lease is judged against the payload cwd while git pushes from the
# inherited repository.
run_split "$REPO_SHA1" "$REPO_SHA1" "git --git-dir=<sha256>/.git --work-tree=<sha256> -c alias.y='!git push --force-with-lease=main:<40-hex>' y (inherited GIT_DIR, blocked)" "git --git-dir=$REPO_SHA256/.git --work-tree=$REPO_SHA256 -c alias.y='!git push --force-with-lease=main:$SHA1_OID origin main' y" 2
run_split "$REPO_SHA256" "$REPO_SHA1" "git --git-dir=<sha1>/.git --work-tree=<sha1> -c alias.y='!git push --force-with-lease=main:<40-hex>' y (40-hex is object id in inherited repo, allowed)" "git --git-dir=$REPO_SHA1/.git --work-tree=$REPO_SHA1 -c alias.y='!git push --force-with-lease=main:$SHA1_OID origin main' y" 0
# The re-expansion MEMO must key on the effective base. A verdict is now a function
# of the base, so one alias STRING reached under two bases is two analyses — and a
# key blind to the base skips the second. Ordered sha1-then-sha256 deliberately:
# the sha1 hop is legitimately allowed (a 40-hex word IS an object id there) and
# memoizes, and a base-blind key then lets the identical text through where the
# same word is a movable ref name. The two single-segment cases below are the
# controls proving each half is decided correctly on its own, so the two-segment
# verdict can only come from the cache.
memo_alias="-c alias.y='!git push --force-with-lease=main:$SHA1_OID origin main' y"
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "control: the alias under a SHA-1 -C alone (40-hex is an object id there, allowed)" "git -C $REPO_SHA1 $memo_alias" 0
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "control: the same alias under a SHA-256 -C alone (40-hex is a ref name there, blocked)" "git -C $REPO_SHA256 $memo_alias" 2
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "the same alias text under a SHA-1 then a SHA-256 -C: the memo must not reuse the first base's verdict (blocked)" "git -C $REPO_SHA1 $memo_alias; git -C $REPO_SHA256 $memo_alias" 2
# `&&` as well as `;` — the collision is in the key, not in the operator, and the
# reparse path is reached identically through both.
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "the same alias text across && rather than ; (blocked)" "git -C $REPO_SHA1 $memo_alias && git -C $REPO_SHA256 $memo_alias" 2
# The sharpest isolation of the KEY as the cause: this differs from the case above
# only by a space inside the alias body — same repositories, same bases, same
# danger, different key. It was already blocked before the base joined the key, so
# it discriminates nothing on its own; it is here to pin that a base-blind key was
# the whole difference, and to fail loudly if the key ever stops covering the body.
memo_alias_sp="-c alias.y='!git  push --force-with-lease=main:$SHA1_OID origin main' y"
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "control: identical bases but one space added to the alias body (a different key, blocked)" "git -C $REPO_SHA1 $memo_alias; git -C $REPO_SHA256 $memo_alias_sp" 2

# The cost of keying on the base: distinct bases mean distinct keys, so the memo
# dedups less and a command alternating bases does strictly more re-expansions.
# This is the case the base-keyed memo perturbs, and it must stay bounded and
# correct rather than merely bounded. Sixteen distinct bases naming the SAME
# SHA-1 repository: every one is a fresh key, so this is 16 analyses where the
# old key spent 1 — well inside HOOK_ALIAS_WORK_MAX (128), which fails closed if
# it is ever exceeded.
memo_many=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  mkdir -p "$REPO_SHA1/d$i"
  memo_many="$memo_many${memo_many:+; }git -C $REPO_SHA1/d$i $memo_alias"
done
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "16 distinct bases in one command, all naming the SHA-1 repo (every hop re-analyzed, still allowed and bounded)" "$memo_many" 0
# The same walk with a SHA-256 base appended: the weakened dedup must not let the
# dangerous tail ride in on the sixteen safe keys ahead of it.
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "16 SHA-1 bases then a SHA-256 one (the dangerous tail is still analyzed, blocked)" "$memo_many; git -C $REPO_SHA256 $memo_alias" 2

# The relocation must not LEAK past the reparse: a second segment after the alias
# one starts from the payload cwd again.
run_split "$REPO_SHA256" "$REPO_SHA256" "a segment after a relocating '!' alias is measured from the payload cwd again (40-hex is a name there, blocked)" "git -C $REPO_SHA1 -c alias.y='!git status' y; git push --force-with-lease=main:$SHA1_OID origin main" 2

# A RELATIVE locating option now resolves against the directory the tool call runs
# in rather than the hook process's. That is the correct origin, and it is the one
# behaviour change a reviewer could mistake for a regression.
run_split "$TEST_TMPDIR" "$TEST_TMPDIR" "relative git -C <basename> with both directories agreeing (unchanged, blocked)" "git -C repo-sha256 push --force-with-lease=main:$SHA1_OID origin main" 2
run_split "$TEST_TMPDIR" "$REPO_SHA1" "relative git -C <basename> resolves against the payload cwd, not the hook process's (object id there, allowed)" "git -C repo-sha1 push --force-with-lease=main:$SHA1_OID origin main" 0
run_split "$TEST_TMPDIR" "$REPO_SHA1" "relative --git-dir rebases onto the payload cwd the same way (object id there, allowed)" "git --git-dir=repo-sha1/.git push --force-with-lease=main:$SHA1_OID origin main" 0
run_split "$TEST_TMPDIR" "$REPO_SHA1" "an ABSOLUTE --git-dir is unaffected by the base (64-hex is a name in the SHA-1 target, blocked)" "git --git-dir=$REPO_SHA1/.git push --force-with-lease=main:$SHA256_OID origin main" 2

# The rest of the chain, mirroring block-noncanonical-commit: payload cwd, then
# CLAUDE_PROJECT_DIR, then `.`. A real payload always carries cwd, so the lower
# rungs are reached only by a degraded one.
run_nocwd "$REPO_SHA256" "no cwd in the payload and no CLAUDE_PROJECT_DIR falls back to the hook process's directory (blocked)" "git push --force-with-lease=main:$SHA1_OID origin main" 2 -u CLAUDE_PROJECT_DIR
run_nocwd "$REPO_SHA256" "no cwd in the payload prefers CLAUDE_PROJECT_DIR over the hook process's directory (object id there, allowed)" "git push --force-with-lease=main:$SHA1_OID origin main" 0 "CLAUDE_PROJECT_DIR=$REPO_SHA1"

# --- env -S / --split-string carries the wrapper's OWN options -----------------
# `-S` exists so a shebang line can pass options to env (`#!/usr/bin/env -S -i
# prog`), so the split words are env's arguments, not just the command. Resuming
# the scan at the command dispatcher instead read a leading option in the split
# string as the COMMAND NAME and abandoned the segment: no git was resolved at
# all, so every form behind it — including a plain --force — went unexamined.
run "env -S '-C <sha256-repo> git push --force-with-lease=main:<40-hex>' (chdir spliced inside the quoted word, blocked)" "env -S '-C $REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main'" 2
run "env --split-string='-C <sha256-repo> git push --force-with-lease=main:<40-hex>' (long form, blocked)" "env --split-string='-C $REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main'" 2
run "env -S'-C <sha256-repo> git push --force-with-lease=main:<40-hex>' (attached operand, blocked)" "env -S'-C $REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main'" 2
run "env -S '-v git push --force' (a valueless leading option no longer hides the force push, blocked)" "env -S '-v git push --force origin main'" 2
run "env -S 'git push --force' (no leading option — already blocked, still blocked)" "env -S 'git push --force origin main'" 2
run "env -S '-C <sha256-repo> git push --force-with-lease=main:<64-hex>' (object id where git runs, allowed)" "env -S '-C $REPO_SHA256 git push --force-with-lease=main:$SHA256_OID origin main'" 0
# GNU env keeps its chdir operand in ONE slot, so a `-C` inside the split string
# is last-wins against an earlier one outside it, never cumulative.
run "env -C <sha1-repo> -S '-C <sha256-repo> git …' (last wins, blocked)" "env -C $REPO_SHA1 -S '-C $REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main'" 2
run_in "$REPO_SHA256" "env -C <sha256-repo> -S '-C <sha1-repo> git …' (last wins the other way, allowed)" "env -C $REPO_SHA256 -S '-C $REPO_SHA1 git push --force-with-lease=main:$SHA1_OID origin main'" 0
# An inert form is not a bypass and must not be treated as one: GNU coreutils
# stops option parsing at the first NAME=VALUE operand, so `-C` becomes the
# command name, git never runs, and there is nothing here to block.
run "env FOO=1 -C <sha256-repo> git push --force-with-lease=main:<40-hex> (NAME=VALUE ends option parsing; git never runs, allowed)" "env FOO=1 -C $REPO_SHA256 git push --force-with-lease=main:$SHA1_OID origin main" 0

# The width probe is the guard's only subprocess, and a command may carry many
# lease expectations. Counting real git invocations catches the cache being lost
# to a subshell — a per-expectation probe would spawn one git each and push a
# blocking PreToolUse hook toward its timeout, where it fails open.
GIT_SHIM_DIR="$TEST_TMPDIR/git-shim"
GIT_CALL_LOG="$TEST_TMPDIR/git-calls"
mkdir -p "$GIT_SHIM_DIR"
cat >"$GIT_SHIM_DIR/git" <<EOF
#!/usr/bin/env bash
printf 'x' >>"$GIT_CALL_LOG"
exec "$(command -v git)" "\$@"
EOF
chmod +x "$GIT_SHIM_DIR/git"
: >"$GIT_CALL_LOG"
many_leases="git push"
for i in 1 2 3 4 5 6 7 8; do
  many_leases="$many_leases --force-with-lease=ref$i:$SHA1_OID"
done
run "eight pinned leases (all allowed)" "$many_leases origin main" 0 "PATH=$GIT_SHIM_DIR:$PATH"
git_calls=$(wc -c <"$GIT_CALL_LOG" | tr -d ' ')
if [[ "$git_calls" == 1 ]]; then
  ok "width probe runs once for eight lease expectations (git invocations: 1)"
else
  bad "width probe should run once for eight lease expectations, ran $git_calls times"
fi
run "git push --force-with-lease=main: (empty expect means ref must not exist, allowed)" "git push --force-with-lease=main: origin main" 0
run "git push --force-with-lease --force-if-includes (mitigated, allowed)" "git push --force-with-lease --force-if-includes" 0
run "git push --force-with-lease=main --force-if-includes (mitigated, allowed)" "git push --force-with-lease=main --force-if-includes origin main" 0
run "git push --force-if-includes alone (no lease, git no-ops it, allowed)" "git push --force-if-includes origin main" 0
run "git push --force-w (unique abbrev of the lease flag, blocked)" "git push --force-w" 2
run "git push --force-w=main:<40-hex> (abbrev flag with full object id, allowed)" "git push --force-w=main:$SHA1_OID origin main" 0
run "git push --force-w --force-i (both abbreviated, mitigated, allowed)" "git push --force-w --force-i" 0
run "git push --force-with-lease --dry-run (preview updates nothing, allowed)" "git push --force-with-lease --dry-run" 0
run "git push --force-with-lease -- --force-if-includes (after --, operand not flag, blocked)" "git push --force-with-lease -- --force-if-includes" 2
run "git push --force-with-lease --force-if-includes --no-force-if-includes (negated mitigation, blocked)" "git push --force-with-lease --force-if-includes --no-force-if-includes origin main" 2
run "git push --force-with-lease --no-force-if-includes --force-if-includes (re-armed mitigation, allowed)" "git push --force-with-lease --no-force-if-includes --force-if-includes origin main" 0
run "git push --force-with-lease --force-i --no-force-i (abbreviated negation, blocked)" "git push --force-with-lease --force-i --no-force-i origin main" 2
run "git push --force-with-lease --force-if-includes --no-force-w (lease negation does not clear the mitigation, allowed)" "git push --force-with-lease --force-if-includes --no-force-w origin main" 0
run "git push --force-with-lease --no-force-with-lease (lease negated, not a lease push, allowed)" "git push --force-with-lease --no-force-with-lease origin main" 0
run "git push --force-with-lease --no-force-with-lease --force-with-lease (lease re-armed, blocked)" "git push --force-with-lease --no-force-with-lease --force-with-lease origin main" 2
run "git push --no-force-with-lease alone (nothing to negate, allowed)" "git push --no-force-with-lease origin main" 0
run "git push pinned lease then --no-force-with-lease (stated expectation negated, allowed)" "git push --force-with-lease=main:$SHA1_OID --no-force-with-lease origin main" 0
run "git push movable lease then --no-force-with-lease (git cancels every previous lease, allowed)" "git push --force-with-lease=main:origin/main --no-force-with-lease origin main" 0
run "git push movable lease, negated, then re-stated (claims re-staked, blocked)" "git push --force-with-lease=main:origin/main --no-force-with-lease --force-with-lease=main:origin/main origin main" 2
run "git push bare + pinned lease over two refs (bare fallback still governs 'other', blocked)" "git push --force-with-lease --force-with-lease=refs/heads/main:$SHA1_OID origin main other" 2
run "git push pinned then bare (order does not rescue the bare fallback, blocked)" "git push --force-with-lease=refs/heads/main:$SHA1_OID --force-with-lease origin main other" 2
run "git push bare + pinned + --force-if-includes (mitigation covers the fallback, allowed)" "git push --force-with-lease --force-with-lease=refs/heads/main:$SHA1_OID --force-if-includes origin main other" 0
run "git push lease pinned to a remote-tracking name (movable at push time, blocked)" "git push --force-with-lease=refs/heads/main:refs/remotes/origin/main origin main" 2
run "git push lease pinned to origin/main shorthand (movable, blocked)" "git push --force-with-lease=main:origin/main origin main" 2
run "git push lease pinned to HEAD (movable, blocked)" "git push --force-with-lease=main:HEAD origin main" 2
run "git push lease pinned to an abbreviated object id (a ref of that name wins, blocked)" "git push --force-with-lease=main:abc123 origin main" 2
run "git push lease pinned to a 4-hex expect that is also a valid ref name (blocked)" "git push --force-with-lease=main:dead origin main" 2
run "git push lease pinned to a 39-hex expect (one short of full width, blocked)" "git push --force-with-lease=main:012345678901234567890123456789012345678 origin main" 2
run "git push lease pinned to a movable name + --force-if-includes (git no-ops the mitigation here, blocked)" "git push --force-with-lease=main:origin/main --force-if-includes origin main" 2
run "git push lease pinned to a 3-char expect (too short to be an object id, blocked)" "git push --force-with-lease=main:abc origin main" 2
run "git push --force-with-lease --force-if-includes --no-dry-run (dry-run negation does not clear the mitigation, allowed)" "git push --force-with-lease --force-if-includes --no-dry-run origin main" 0
run "git push pinned lease + --no-force-if-includes (stated expectation stands without the mitigation, allowed)" "git push --force-with-lease=main:$SHA1_OID --no-force-if-includes origin main" 0
# git's apply_cas() returns on the FIRST lease entry matching the ref being
# updated, so a repeated ref is decided by the earlier spelling alone.
run "git push same ref pinned first, movable second (git uses the first, allowed)" "git push --force-with-lease=main:$SHA1_OID --force-with-lease=main:origin/main origin main" 0
run "git push pinned main:<sha> then equivalent refs/heads/main spelling (allowed)" "git push --force-with-lease=main:$SHA1_OID --force-with-lease=refs/heads/main:origin/main origin main" 0
run "git push same ref movable first, pinned second (git uses the first, blocked)" "git push --force-with-lease=main:origin/main --force-with-lease=main:$SHA1_OID origin main" 2
run "git push same ref no-expect first, pinned second (first is tracking-based, blocked)" "git push --force-with-lease=main --force-with-lease=main:$SHA1_OID origin main" 2
run "git push same ref no-expect first, pinned second, mitigated (allowed)" "git push --force-with-lease=main --force-with-lease=main:$SHA1_OID --force-if-includes origin main" 0
run "git push different refs, one pinned one movable (both entries live, blocked)" "git push --force-with-lease=main:$SHA1_OID --force-with-lease=other:origin/other origin main other" 2
# A block message is a producer-facing prescription, so the form it names must be
# one this guard accepts. Detection is static over the literal command string —
# substitutions are never evaluated — so a `$(…)` in the <expect> slot arrives as
# an unresolved name and is blocked by the very message prescribing it. Asserted
# on the message text rather than an exit code: both cases below already exit 2,
# and it is the prescription that was wrong.
# shellcheck disable=SC2016  # '$(' is the substitution syntax being asserted absent, not an expansion
for lease_case in "--force-with-lease=main:origin/main" "--force-with-lease"; do
  lease_msg=$(cd "$REPO_SHA1" && bash "$HOOK" <<<"$(command_json "git push $lease_case origin main")" 2>&1)
  assert_absent "lease block message ($lease_case) prescribes no command substitution" \
    "$lease_msg" '$('
  assert_contains "lease block message ($lease_case) prescribes a resolved literal object id" \
    "$lease_msg" '<full-sha>'
done

run "git push (plain, allowed)" "git push" 0
run "git push -u origin main (allowed)" "git push -u origin main" 0
run "git push -o f (option value f, allowed)" "git push -o f origin main" 0
run "git push -ofoo (attached option value, allowed)" "git push -ofoo origin main" 0
run "git push --dry-run --force (push dry run disarms, allowed)" "git push --dry-run --force origin main" 0
run "git push -n -f (short dry run disarms, allowed)" "git push -n -f origin main" 0
run "git push --dry-run --no-dry-run --force (negated dry run, blocked)" "git push --dry-run --no-dry-run --force origin main" 2
run "git push --mi backup (abbreviated mirror, blocked)" "git push --mi backup" 2
run "git push --m backup (shortest unique mirror abbrev, blocked)" "git push --m backup" 2
run "cd x && git push --force (compound, blocked)" "cd x && git push --force" 2
run "quoted push --force prose (allowed)" 'echo "git push --force is banned"' 0

# --- reset-hard ---------------------------------------------------------------
run "git reset --hard (blocked)" "git reset --hard" 2
run "git reset --h HEAD (abbreviated hard, blocked)" "git reset --h HEAD" 2
run "git reset --ha HEAD (abbreviated hard, blocked)" "git reset --ha HEAD" 2
run "git reset --hard HEAD~1 (blocked)" "git reset --hard HEAD~1" 2
run "git reset --soft HEAD~1 (allowed)" "git reset --soft HEAD~1" 0
run "git reset (mixed, allowed)" "git reset" 0
run "git reset --keep (allowed)" "git reset --keep HEAD~1" 0
run "git reset --pathspec-from paths (abbreviated value skipped, allowed)" "git reset --pathspec-from paths" 0
run "git commit -m 'reset --hard' (message literal, allowed)" "git commit -m 'reset --hard'" 0

# --- clean-force --------------------------------------------------------------
run "git clean -f (blocked)" "git clean -f" 2
run "git clean -fd (blocked)" "git clean -fd" 2
run "git clean -fdx (blocked)" "git clean -fdx" 2
run "git clean -fen (e absorbs n as its value, blocked)" "git clean -fen" 2
run "git clean -fe -n (trailing e absorbs -n, blocked)" "git clean -fe -n" 2
run "git clean -nef (dry-run before e, allowed)" "git clean -nef" 0
run "git clean --force (blocked)" "git clean --force" 2
run "git clean -n (dry run, allowed)" "git clean -n" 0
run "git clean -nd (dry run bundle, allowed)" "git clean -nd" 0 # spellchecker:disable-line
run "git clean -n -fd (dry run disarms force, allowed)" "git clean -n -fd" 0
run "git clean -fdn (dry run in force bundle, allowed)" "git clean -fdn" 0
run "git clean --dry-run -f (long dry run, allowed)" "git clean --dry-run -f" 0
run "git clean -f -e --dry-run (dry-run as exclude value, blocked)" "git clean -f -e --dry-run" 2
run "git clean --f (abbreviated force, blocked)" "git clean --f" 2
run "git clean -f -- --dry-run (dry-run pathspec after --, blocked)" "git clean -f -- --dry-run" 2
run "git clean --dry-run --no-dry-run -f (negated dry run, blocked)" "git clean --dry-run --no-dry-run -f" 2
run "git clean --no-dry-run -n -f (dry run after negation, allowed)" "git clean --no-dry-run -n -f" 0
run "git clean -f --ex --dry-run (abbrev exclude eats dry-run, blocked)" "git clean -f --ex --dry-run" 2

# --- checkout-dot / restore-dot ----------------------------------------------
run "git checkout . (blocked)" "git checkout ." 2
run "git checkout -- . (blocked)" "git checkout -- ." 2
run "git checkout .github/workflows (path-scoped, allowed)" "git checkout .github/workflows" 0
run "git checkout main (branch switch, allowed)" "git checkout main" 0
run "git checkout -b feat/x (new branch, allowed)" "git checkout -b feat/x" 0
run "git restore . (blocked)" "git restore ." 2
run "git restore -- . (blocked)" "git restore -- ." 2
run "git restore --worktree . (blocked)" "git restore --worktree ." 2
run "git restore --staged --worktree . (blocked)" "git restore --staged --worktree ." 2
run "git restore --staged . (index-only, allowed)" "git restore --staged ." 0
run "git restore path/file (path-scoped, allowed)" "git restore path/file" 0
run "git restore --source HEAD~1 file (source value, allowed)" "git restore --source HEAD~1 file" 0
run "git checkout :/ (root-magic pathspec, blocked)" "git checkout :/" 2
run "git restore :/ (root-magic pathspec, blocked)" "git restore :/" 2
run "git restore ':(top)' (top-magic pathspec, blocked)" "git restore ':(top)'" 2
run "git restore ':(literal,top)' (reordered top magic, blocked)" "git restore ':(literal,top)'" 2
run "git restore ':(literal)x' (non-top magic, allowed)" "git restore ':(literal)x'" 0
run "git restore ':(top)src/a' (top magic with subpath, allowed)" "git restore ':(top)src/a'" 0
run "git restore ':(top,glob)**' (glob-all top, blocked)" "git restore ':(top,glob)**'" 2
run "git restore '*' (bare wildcard-all, blocked)" "git restore '*'" 2
run "git restore --staged --w . (abbrev worktree, blocked)" "git restore --staged --w ." 2
run "git checkout -- . (dot after end-of-options, blocked)" "git checkout -- ." 2
run "git checkout -- -f (pathspec named -f, allowed)" "git checkout -- -f" 0
run "git reset -- --hard (pathspec named --hard, allowed)" "git reset -- --hard" 0
run "git checkout --pathspec-from-file=paths (unverifiable pathspec file, blocked)" "git checkout --pathspec-from-file=paths" 2
run "git restore --pathspec-from-file paths (unverifiable pathspec file, blocked)" "git restore --pathspec-from-file paths" 2
run "git checkout --pathspec-from paths (abbreviated pathspec file, blocked)" "git checkout --pathspec-from paths" 2
run "git restore --pathspec-fr paths (shortest unique abbreviation, blocked)" "git restore --pathspec-fr paths" 2
run "git restore --pathspec-from=paths (abbreviated = form, blocked)" "git restore --pathspec-from=paths" 2
run "git checkout --pathspec-file-nul (boolean flag alone, allowed)" "git checkout --pathspec-file-nul" 0
run "git restore ':/*' (root-magic wildcard, blocked)" "git restore ':/*'" 2
run "git restore ':/**' (root-magic recursive wildcard, blocked)" "git restore ':/**'" 2
run "git checkout ':/*' (root-magic wildcard, blocked)" "git checkout ':/*'" 2
run "git restore ':/src' (root magic with subpath, allowed)" "git restore ':/src'" 0
run "git restore ./ (dot-slash worktree discard, blocked)" "git restore ./" 2
run "git restore .. (parent-dir discard, blocked)" "git restore .." 2
run "git checkout -- ./ (dot-slash after end-of-options, blocked)" "git checkout -- ./" 2
run "git restore '?*' (question-mark wildcard-all, blocked)" "git restore '?*'" 2
run "git checkout '?*' (question-mark wildcard-all, blocked)" "git checkout '?*'" 2
run "git restore './*' (dot-slash wildcard-all, blocked)" "git restore './*'" 2
run "git restore ':/?*' (root-magic question wildcard, blocked)" "git restore ':/?*'" 2
run "git restore '*.md' (extension-scoped wildcard, allowed)" "git restore '*.md'" 0
run "git restore ':(exclude)zzz' (exclude-only pathspec, blocked)" "git restore ':(exclude)zzz'" 2
run "git checkout ':!zzz' (exclude-only short magic, blocked)" "git checkout ':!zzz'" 2
run "git restore ':^zzz' (exclude-only caret magic, blocked)" "git restore ':^zzz'" 2
run "git restore ':(exclude)sub' root.txt (positive scopes exclude, allowed)" "git restore ':(exclude)sub' root.txt" 0
run "git checkout main ':!docs' (tree-ish plus exclude-only, blocked)" "git checkout main ':!docs'" 2
run "git checkout HEAD -- ':!docs' (tree-ish, exclude after --, blocked)" "git checkout HEAD -- ':!docs'" 2
run "git checkout main ':!docs' src/ (positive path scopes, allowed)" "git checkout main ':!docs' src/" 0
run "git checkout ':!a' src/ (exclude then positive, allowed)" "git checkout ':!a' src/" 0
run "git restore --conflict merge ':(exclude)docs' (option value not positive, blocked)" "git restore --conflict merge ':(exclude)docs'" 2
run "git restore --c merge ':(exclude)docs' (abbrev conflict value, blocked)" "git restore --c merge ':(exclude)docs'" 2
run "git restore --so HEAD ':(exclude)docs' (abbrev source value, blocked)" "git restore --so HEAD ':(exclude)docs'" 2
run "git restore --so HEAD file (abbrev source, scoped, allowed)" "git restore --so HEAD file" 0
run "git checkout --c merge HEAD ':!docs' (abbrev conflict value, blocked)" "git checkout --c merge HEAD ':!docs'" 2
run "git restore ':' (bare no-pathspec marker, blocked)" "git restore ':'" 2
run "git restore '::' (double-colon marker, blocked)" "git restore '::'" 2
run "git checkout ':(literal)' (empty non-top magic, blocked)" "git checkout ':(literal)'" 2
run "git checkout ':(glob)' (empty glob magic, blocked)" "git checkout ':(glob)'" 2
run "git checkout -f (forced discard, blocked)" "git checkout -f" 2
run "git checkout --force main (forced switch, blocked)" "git checkout --force main" 2
run "git checkout --f main (abbreviated force, blocked)" "git checkout --f main" 2
run "git checkout -bf (attached branch name f, allowed)" "git checkout -bf" 0
run "git switch -f main (forced switch, blocked)" "git switch -f main" 2
run "git switch --discard-changes main (blocked)" "git switch --discard-changes main" 2
run "git switch --di other (shortest discard abbrev, blocked)" "git switch --di other" 2
run "git switch --dis other (discard abbrev, blocked)" "git switch --dis other" 2
run "git switch --detach main (detach, not discard, allowed)" "git switch --detach main" 0
run "git switch --de main (detach abbrev, allowed)" "git switch --de main" 0
run "git switch main (plain switch, allowed)" "git switch main" 0
run "git switch -c feat/x (create, allowed)" "git switch -c feat/x" 0
run "git switch -cfix (attached branch name with f, allowed)" "git switch -cfix" 0
run "git switch -Cfix (attached force-create name, allowed)" "git switch -Cfix" 0
run "git switch -cfix -f (force after attached value, blocked)" "git switch -cfix -f" 2

# --- not blocked by design ----------------------------------------------------
run "git branch -D feat/x (reflog-recoverable, allowed)" "git branch -D feat/x" 0
run "git branch -d feat/x (safe delete, allowed)" "git branch -d feat/x" 0
run "git status (read-only, allowed)" "git status" 0
run "empty command (allowed)" "" 0

# --- argv-faithful regressions ------------------------------------------------
run "git push \"--force\" (quoted flag, blocked)" 'git push "--force"' 2
run "git push --for'ce' (partial-quote flag, blocked)" "git push --for'ce'" 2
run "\"git\" push --force (quoted executable, blocked)" '"git" push --force' 2
run "git \$'--force' push? no — push \$'--force' (ANSI-C flag, blocked)" "git push \$'--force'" 2
run "echo git push --force (git as argument, allowed)" "echo git push --force" 0
run "echo \"a && git reset --hard\" (operator in quotes, allowed)" 'echo "a && git reset --hard"' 0
run "grep 'git clean -f' notes.md (quoted pattern, allowed)" "grep 'git clean -f' notes.md" 0
run "git -C . push --force (arg-consuming global, blocked)" "git -C . push --force" 2
run "env -i git push --force (wrapper, blocked)" "env -i git push --force" 2
run "env -S 'git push --force' (split-string, blocked)" "env -S 'git push --force'" 2
run "env -S quoted flag (inner-quote split-string, blocked)" "env -S 'git push \"--force\"'" 2
run "bash -lc 'git reset --hard' (shell -c wrapper, blocked)" "bash -lc 'git reset --hard'" 2
run "sh -c 'git push --force' (shell -c wrapper, blocked)" "sh -c 'git push --force'" 2
run "bash -c compound (wrapped operator chain, blocked)" "bash -c 'git status && git clean -fd'" 2
run "bash -c 'git status' (wrapped read-only, allowed)" "bash -c 'git status'" 0
run "bash script.sh (script file, not -c, allowed)" "bash script.sh" 0
run "env --unset FOO git push --force (two-word unset, blocked)" "env --unset FOO git push --force" 2
run "bash -O extglob -c 'git reset --hard' (shopt operand, blocked)" "bash -O extglob -c 'git reset --hard'" 2
run "bash --rcfile /dev/null -c 'git reset --hard' (rcfile operand, blocked)" "bash --rcfile /dev/null -c 'git reset --hard'" 2
run "bash --init-file rc -c 'git checkout .' (init-file operand, blocked)" "bash --init-file rc -c 'git checkout .'" 2
run "if true; then git reset --hard; fi (then-body, blocked)" "if true; then git reset --hard; fi" 2
run "while true; do git clean -fd; done (do-body, blocked)" "while true; do git clean -fd; done" 2
run "if false; then :; else git push --force; fi (else-body, blocked)" "if false; then :; else git push --force; fi" 2
run "if git reset --hard; then :; fi (if-condition, blocked)" "if git reset --hard; then :; fi" 2
run "git reset --hard>/tmp/out (attached redirection, blocked)" "git reset --hard>/tmp/out" 2
run "git reset --hard 2>&1 (fd-dup redirection, blocked)" "git reset --hard 2>&1" 2
run "git checkout . >log (redirect after dot, blocked)" "git checkout . >log" 2
run "git clean -f > -n (redirect target not a dry-run flag, blocked)" "git clean -f > -n" 2
run "git push origin main >push.log (redirect target dropped, allowed)" "git push origin main >push.log" 0
run "cat <(git reset --hard) (process substitution, blocked)" "cat <(git reset --hard)" 2
run "diff <(git status) <(git reset --hard) (second substitution, blocked)" "diff <(git status) <(git reset --hard)" 2
run "cat <(git status) (safe substitution, allowed)" "cat <(git status)" 0
run "heredoc body with git reset (stdin, not a command, allowed)" $'cat >notes <<EOF\ngit reset --hard\nEOF' 0
run "quoted-delimiter heredoc with git push --force (allowed)" $'cat <<\'EOF\'\ngit push --force\nEOF' 0
run "tab-indented heredoc <<- body (allowed)" $'cat <<-EOF\n\tgit reset --hard\n\tEOF' 0
run "real git reset --hard after a heredoc (blocked)" $'cat <<EOF\nhello\nEOF\ngit reset --hard' 2
run "here-string git reset --hard (not a heredoc, blocked)" $'git reset --hard <<<input' 2
run "git -c alias.rh='reset --hard' rh (inline git alias, blocked)" "git -c alias.rh='reset --hard' rh" 2
run "git -c alias.nuke='!git reset --hard' nuke (inline shell alias, blocked)" "git -c alias.nuke='!git reset --hard' nuke" 2
run "git -c alias.st=status st (safe alias, allowed)" "git -c alias.st=status st" 0
run "git -c alias.rh='reset --hard' status (alias defined, not run, allowed)" "git -c alias.rh='reset --hard' status" 0
# --config-env=<key>=<envvar> holds the alias expansion in an ENVIRONMENT VARIABLE, and
# this guard never reads that value: its origin — an ambient var, an inline/`env` prefix,
# an `export`, `set -a`, or a nested `bash -c` in any wrapper — is the recurring fail-open
# surface. An env-defined alias for the INVOKED subcommand is refused by SHAPE alone.
run "env-defined alias for the invoked sub (blocked by shape)" "git --config-env=alias.rh=AV rh" 2
run "env-defined alias, two-word --config-env form (blocked)" "git --config-env alias.rh=AV rh" 2
run "env-defined alias, benign-looking value STILL blocked (value never read)" "git --config-env=alias.st=AV st" 2 AV=status
run "env-defined alias, case-folded key (blocked)" "git --config-env=alias.RH=AV rh" 2
run "env-defined alias, non-identifier env name (blocked)" "git --config-env=alias.rh=bad-rh rh" 2
run "env-defined alias, leading-dash env name (blocked)" "env -- '-AV=x' git --config-env=alias.rh=-AV rh" 2
run "env value last-wins over an inline decoy for the same key (blocked)" "git -c alias.rh=status --config-env=alias.rh=AV rh" 2
# Inline (-c/--config) aliases still carry the expansion literally and are resolved.
run "inline dangerous alias (blocked)" "git -c alias.rh='reset --hard' rh" 2
run "inline alias, case-folded subcommand (blocked)" "git -c alias.rh='reset --hard' RH" 2
run "inline alias, case-folded key (blocked)" "git -c alias.RH='reset --hard' rh" 2
# git also reads the `alias.<sub>.command` subkey as the alias definition
# (`git -c alias.rh.command='reset --hard' rh` runs it); the guard classifies that
# spelling as an alias too, inline and by --config-env shape.
run "inline dangerous .command-subkey alias (blocked)" "git -c alias.rh.command='reset --hard' rh" 2
run "env-defined .command-subkey alias for the invoked sub (blocked by shape)" "git --config-env=alias.rh.command=AV rh" 2
run ".command-subkey alias, case-folded key (blocked)" "git -c alias.RH.command='reset --hard' rh" 2
# A non-`command` alias subkey is not an alias to git, so it must not be blocked.
run "non-command alias subkey is not an alias (allowed)" "git -c alias.rh.nope='reset --hard' rh" 0
# MAX-DANGER UNION: which spelling git runs when both are set is version-dependent, so a
# benign value in one spelling must never mask a dangerous value in the other — the guard
# blocks if EITHER spelling is dangerous, and allows only when BOTH are benign.
run "dangerous plain masked by a benign .command (blocked by union)" "git -c alias.rh='reset --hard' -c alias.rh.command=status rh" 2
run "dangerous .command masked by a benign plain (blocked by union)" "git -c alias.rh=status -c alias.rh.command='reset --hard' rh" 2
run "dangerous plain, benign .command decoy first (blocked by union)" "git -c alias.rh.command=status -c alias.rh='reset --hard' rh" 2
run "both spellings benign (allowed)" "git -c alias.rh=status -c alias.rh.command=log rh" 0
# Union on the --config-env shape path: an env spelling refuses even when the sibling
# inline spelling is benign (both command-line orders).
run "env plain spelling refuses despite a benign inline .command (blocked)" "git --config-env=alias.rh=AV -c alias.rh.command=status rh" 2
run "env .command spelling refuses despite a benign inline plain (blocked)" "git --config-env=alias.rh.command=AV -c alias.rh=status rh" 2

# The env-defined alias is refused wherever it APPEARS, through any wrapper — no env
# propagation is tracked, so every prior env-carrying bypass (export / set -a / command
# prefix / bash -c / snapshot-global collision) is closed by construction.
run "env-defined alias inside an inline '!' shell alias (blocked)" "git -c \"alias.sh=!git --config-env=alias.rh=AV rh\" sh" 2
# An inline alias whose expansion is itself a `--config-env` alias for the invoked sub
# runs at recursion depth 2, where the SHAPE refusal must still fire (real git runs it:
# reverts the worktree). Verified against ground truth.
run "wrapping inline alias expands to a --config-env alias (depth-2 shape refusal, blocked)" \
  "git -c alias.rh='--config-env=alias.foo=AV foo' rh" 2 "AV=reset --hard"
run "env-defined alias inside an env-prefixed bash -c (blocked)" "AV='reset --hard' bash -c 'git --config-env=alias.rh=AV rh'" 2
run "env-defined alias after export in a shell-alias body (blocked)" "git -c \"alias.sh=!export AV='reset --hard'; git --config-env=alias.rh=AV rh\" sh" 2
run "env-defined alias after 'then export' in a compound command (blocked)" "git -c 'alias.sh=!if true; then export AV=\"reset --hard\"; fi; git --config-env=alias.rh=AV rh' sh" 2
run "env-defined alias after 'export NAME; NAME=val' (blocked)" "git -c 'alias.sh=!export AV; AV=\"reset --hard\"; git --config-env=alias.rh=AV rh' sh" 2
run "env-defined alias after an assignment-prefixed export (blocked)" "git -c 'alias.sh=!AV=\"reset --hard\" export AV; git --config-env=alias.rh=AV rh' sh" 2
run "env-defined alias after 'set -a; NAME=val' allexport (blocked)" "set -a; AV='reset --hard'; git --config-env=alias.rh=AV rh" 2
run "env-defined alias whose env name collides with an internal global (blocked)" "git --config-env=alias.rh=HOOK_ENV_SNAPSHOT_OK rh" 2 "HOOK_ENV_SNAPSHOT_OK=reset --hard"

# ACCEPTANCE — decidable safe WITHOUT reading any value, so still allowed:
run "--config-env setting a NON-alias key (allowed)" "git --config-env=core.pager=PAGERVAR status" 0
run "--config-env alias for a subcommand that is NOT invoked (allowed)" "git --config-env=alias.foo=AV status" 0
run "inline value last-wins over an earlier --config-env for the same key (allowed)" "git --config-env=alias.rh=AV -c alias.rh=status rh" 0
# A `$( )` env name is command-substituted by the shell before git and split by the
# static parser — neither evaluates it, so no exec and nothing dangerous runs (git-fatal).
rm -f "$TEST_TMPDIR/pwned-dg"
run "injection-shaped config-env env name (allowed — never evaluated)" \
  "git --config-env=alias.rh=\$(touch $TEST_TMPDIR/pwned-dg) rh" 0
assert_file_absent "config-env injection: no exec for a shell-metachar env name" "$TEST_TMPDIR/pwned-dg"
run "command -p git reset --hard (command wrapper option, blocked)" "command -p git reset --hard" 2
run "command -- git reset --hard (command end-of-options, blocked)" "command -- git reset --hard" 2
run "exec -c git reset --hard (exec wrapper option, blocked)" "exec -c git reset --hard" 2
run "command git status (wrapper, no dangerous op, allowed)" "command git status" 0
run "command -v git reset --hard (introspection probe, allowed)" "command -v git reset --hard" 0
run "command -V git commit (introspection probe, allowed)" "command -V git commit" 0
run "command -pv git reset --hard (probe bundle with v, allowed)" "command -pv git reset --hard" 0
run "git -c alias.x='!git' x reset --hard (shell alias appends args, blocked)" "git -c alias.x='!git' x reset --hard" 2
run 'git -c alias.pf=push "--force" pf origin main (quoted alias, blocked)' 'git -c alias.pf='"'"'push "--force"'"'"' pf origin main' 2
run "git push --push-op --dry-run --force origin (abbrev push-option eats dry-run, blocked)" "git push --push-op --dry-run --force origin" 2
run "git push --push-option ci --force origin (full push-option value, blocked)" "git push --push-option ci --force origin" 2
run "git push --recurse-submodules=check origin (non-value long option, allowed)" "git push --recurse-submodules=check origin" 0
run "git restore --staged --worktree --no-worktree . (index-only, allowed)" "git restore --staged --worktree --no-worktree ." 0
run "git restore --staged --no-w . (abbrev no-worktree, allowed)" "git restore --staged --no-w ." 0
run "git restore --no-worktree --worktree . (worktree re-armed, blocked)" "git restore --no-worktree --worktree ." 2
run "git restore --staged --no-staged . (staged cleared, worktree discard, blocked)" "git restore --staged --no-staged ." 2

# --- #964: git chains aliases — re-expansion recurses to the invoked op --------
# git expands an alias whose first word is itself an alias, so a dangerous op
# reached through a SECOND (or later) hop must still block. Every command-line
# -c/--config-env global rides into each hop (so a second-hop --config-env alias
# is refused by shape), and the recursion stops on git's own alias-loop.
# Case C — plain two-hop inline chain (rh -> foo -> reset --hard).
run "#964 case C: two-hop inline alias chain to reset --hard (blocked)" \
  "git -c alias.rh=foo -c alias.foo='reset --hard' rh" 2
# H1 — second hop defined via --config-env (env-shaped, refused by shape); the
# global is carried into the nested hop by the widened splice.
run "#964 H1: inline first hop, --config-env second hop (blocked by shape)" \
  "git -c alias.rh=foo --config-env=alias.foo=AV rh" 2 "AV=reset --hard"
# H2 — same defect with the --config-env global placed BEFORE the -c global.
run "#964 H2: --config-env before -c, chained to the invoked sub (blocked)" \
  "git --config-env=alias.foo=AV -c alias.rh=foo rh" 2 "AV=reset --hard"
# Three inline hops.
run "#964 three-hop inline chain to reset --hard (blocked)" \
  "git -c alias.a=b -c alias.b=c -c alias.c='reset --hard' a" 2
# Second hop spelled via the alias.<sub>.command subkey.
run "#964 .command-spelled second hop to reset --hard (blocked)" \
  "git -c alias.rh=foo -c alias.foo.command='reset --hard' rh" 2
# Benign controls — a chain to a safe terminal op still ALLOWS, and an alias
# cycle terminates (git's alias-loop stop) and allows without hanging.
run "#964 benign two-hop chain to a safe subcommand (allowed)" \
  "git -c alias.a=b -c alias.b=status a" 0
run "#964 alias cycle terminates and allows (no hang)" \
  "git -c alias.a=b -c alias.b=a a" 0
# A `!` shell alias runs in a NEW git process whose alias-loop guard starts
# empty, so a body that re-invokes a name from the outer chain is re-expanded
# there — the reparse must not inherit the outer chain's seen-set.
run "#964 shell-alias body re-invoking the outer chain name (blocked)" \
  "git -c alias.a='!git -c alias.a=\"reset --hard\" a' a" 2
run "#964 shell-alias body re-invoking an undefined inner name (allowed, no hang)" \
  "git -c alias.a='!git a' a" 0

# --- alias-chain traversal stays proportional to the chain's LENGTH ------------
# Each hop re-checks BOTH alias spellings, so re-expansion branches 2x per hop
# unless equivalent states collapse: before the traversal bounds a 10-hop chain
# defining both spellings cost 5.4s, and each further hop doubled it. These cases
# therefore assert a hard wall-clock CEILING as well as the exit code — an
# exit-code-only assertion passes at any runtime and would not see the regression.
#
# run_bounded <label> <command> <expected-exit> <seconds>: `timeout` reports 124
# when the ceiling elapses, which must read as the failure it is rather than as
# an unexpected exit code.
run_bounded() {
  local label="$1" command="$2" expected="$3" secs="$4" rc
  (cd "$REPO_SHA1" && timeout "$secs" bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1)
  rc=$?
  if ((rc == 124)); then
    bad "$label: exceeded the ${secs}s ceiling — alias traversal is not bounded"
  else
    assert_exit "$label" "$expected" "$rc"
  fi
}

# alias_chain <hops> <terminal> [diverge] — an N-hop chain where every hop
# defines both `alias.aN` and `alias.aN.command`. They expand identically by
# default (equivalent states, collapsed by memoization); `diverge` gives each
# spelling its own trailing word so no two analysis paths share a state and only
# the traversal budget can stop the walk.
alias_chain() {
  local n="$1" terminal="$2" mode="${3:-same}" cmd="git" i
  for ((i = 1; i < n; i++)); do
    if [[ "$mode" == diverge ]]; then
      cmd+=" -c alias.a$i='a$((i + 1)) --x$i' -c alias.a$i.command='a$((i + 1)) --y$i'"
    else
      cmd+=" -c alias.a$i=a$((i + 1)) -c alias.a$i.command=a$((i + 1))"
    fi
  done
  printf '%s' "$cmd -c alias.a$n='$terminal' -c alias.a$n.command='$terminal' a1"
}

# The SAFE terminal is the timing case: it exhausts the whole tree, so before the
# bounds it ran past this ceiling (verified — 20 hops did not finish in 30s).
run_bounded "traversal: 20-hop dual-spelling chain to a safe op (allowed, bounded)" \
  "$(alias_chain 20 status)" 0 30
# Coverage is not what the collapse trades away: the same depth still reaches a
# dangerous terminal op and blocks. (This one always returned fast — the walk exits
# on the first path that finds the op — so it asserts reach, not runtime.)
run_bounded "traversal: 20-hop dual-spelling chain to reset --hard (blocked, bounded)" \
  "$(alias_chain 20 'reset --hard')" 2 30
# A long chain that does NOT branch (one spelling per hop) must stay allowed —
# the budget bounds branching, not depth. Ceiling-guarded too: a regression that
# made this one branch would otherwise hang the suite rather than fail it.
run_bounded "traversal: 60-hop single-spelling chain to a safe op (allowed)" \
  "$(
    cmd="git"
    for ((i = 1; i < 60; i++)); do cmd+=" -c alias.a$i=a$((i + 1))"; done
    printf '%s' "$cmd -c alias.a60=status a1"
  )" 0 30
# Divergent spellings defeat state collapse, so the budget is what stops the walk:
# fail CLOSED rather than stall the hook.
run_bounded "traversal: divergent-spelling chain exhausts the budget (blocked, bounded)" \
  "$(alias_chain 12 status diverge)" 2 30
budgetout=$(cd "$REPO_SHA1" && timeout 30 bash "$HOOK" <<<"$(command_json "$(alias_chain 12 status diverge)")" 2>&1)
assert_contains "traversal: budget block names the re-expansion ceiling" \
  "$budgetout" "re-expansions"

# --- allow-list ---------------------------------------------------------------
run "allow-list push-force → allowed" "git push --force" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list push-force,reset-hard → reset allowed" "git reset --hard" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force,reset-hard
run "allow-list push-force only → clean still blocked" "git clean -fd" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list empty → blocked" "git push --force" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=
run "allow-list push-lease-unsafe → bare lease allowed" "git push --force-with-lease" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-lease-unsafe
run "allow-list push-force only → bare lease still blocked" "git push --force-with-lease" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force

# --- kill switch ---------------------------------------------------------------
run "kill switch off → no-op despite push --force" "git push --force" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED=false

# --- over-length command fails CLOSED ------------------------------------------
long_cmd="echo $(printf 'a%.0s' {1..20000})"
run "command over the parse cap (fail-closed, blocked)" "$long_cmd" 2
run "allow-list cannot bypass the parse cap (still blocked)" "$long_cmd" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=too-long

# --- telemetry: block emits a `blocked` envelope --------------------------------
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(command_json 'git push --force')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "block-dangerous-git"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: subject Bash:git" "$(jq -r '.data.subject' "$TEL")" "Bash:git"
  assert_contains "telemetry: form push-force" "$(jq -r '.data.form' "$TEL")" "push-force"
else
  bad "telemetry: no envelope written on block"
fi

# --- PowerShell tool coverage ------------------------------------------------
# The guard is matched on Bash|PowerShell. PowerShell-simple dangerous ops are
# caught; push-shaped PowerShell the guard cannot parse fails closed.
# Same payload-cwd discipline as run_in: a PowerShell payload carries `cwd` too,
# and the lease case below is width-judged, so leaving it out would measure
# CLAUDE_PROJECT_DIR — whatever repository the ambient session happens to be in.
pwsh_command_json_cwd() {
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" \
    '{tool_name:"PowerShell",tool_input:{command:$c},cwd:$d}'
}
run_pwsh() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc
  (cd "$REPO_SHA1" && env "$@" bash "$HOOK" <<<"$(pwsh_command_json_cwd "$command" "$REPO_SHA1")" >/dev/null 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
# The tool name moved to the third jq field when `.cwd` was added. A payload
# MISSING cwd must still read it from the right slot, or a PowerShell command
# would silently be classified as Bash and the PowerShell-specific fail-closed
# sinks would never fire.
run_pwsh_nocwd() {
  local label="$1" command="$2" expected="$3" rc
  (cd "$REPO_SHA1" && bash "$HOOK" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_pwsh_nocwd "PS: git --% reset --hard with NO cwd in the payload (tool name still reads as PowerShell, fail-closed block)" \
  "git --% reset --hard" 2
run_pwsh "PS: git push --force (blocked)" "git push --force" 2
run_pwsh "PS: git reset --hard (blocked)" "git reset --hard" 2
run_pwsh "PS: git push --force-with-lease (no expected value, blocked)" "git push --force-with-lease" 2
run_pwsh "PS: git push --force-with-lease=main:<40-hex> (immutable expectation, allowed)" "git push --force-with-lease=main:0123456789abcdef0123456789abcdef01234567" 0
run_pwsh "PS: git push (plain, allowed)" "git push origin main" 0
run_pwsh "PS: git status (allowed)" "git status" 0
run_pwsh "PS: backtick-continued force push (fail-closed block)" \
  "$(printf 'git push `\n --force')" 2

# This guard owns destructive non-commit forms (reset/clean/checkout/restore), so
# unlike the commit/push guards it cannot defer an unparsable NON-commit/push git
# command — it must fail closed on ANY git-shaped PowerShell it cannot parse.
run_pwsh "PS: git --% reset --hard (stop-parsing token, fail-closed block)" \
  "git --% reset --hard" 2
run_pwsh "PS: git --% clean -fd (stop-parsing token, fail-closed block)" \
  "git --% clean -fd" 2
run_pwsh "PS: backtick-continued git reset --hard (fail-closed block)" \
  "$(printf 'git `\n reset --hard')" 2
# Single-quoted `$(...)` is deliberately literal PowerShell subexpression text
# (the construct under test), not a Bash expansion.
# shellcheck disable=SC2016
run_pwsh "PS: git checkout via subexpression (fail-closed block)" \
  'git checkout $(Get-Branch)' 2
# Negative control: a non-git unparsable PowerShell command is not this guard's
# concern — no over-block past git.
# shellcheck disable=SC2016
run_pwsh "PS: non-git unparsable command (allowed — not git-shaped)" \
  'Remove-Item $(Get-Foo)' 0

# --- #2592: git probe is command-position, not a substring -----------------------
# A PowerShell scriptblock (`{}`) is ordinary idiomatic PowerShell. The sink used
# to engage on ANY `git` substring — including `.git` directory names and
# hyphenated identifiers like `block-dangerous-git` / `NO-GIT` — then fail closed
# on the braces. Command-position matching leaves those alone while still
# catching a real git invocation paired with the same braces.
# shellcheck disable=SC2016
run_pwsh "PS: .git directory name in scriptblock (allowed — #2592, no git command)" \
  "Get-ChildItem -LiteralPath \$p -Recurse -Force -Directory | Where-Object { \$_.Name -in @('node_modules','obj','bin','.git') } | ForEach-Object { \$_.FullName }" 0
run_pwsh "PS: hyphenated -git identifier in scriptblock (allowed — #2592)" \
  "foreach (\$x in @('alpha-block-dangerous-git')) { Write-Host \$x }" 0
run_pwsh "PS: NO-GIT label in scriptblock (allowed — #2592)" \
  "foreach (\$x in @('NO-GIT')) { Write-Host \$x }" 0
# Quoted argument text naming git/PowerShell must not engage the sink either —
# the title string is data, not a command word (#2592 comment).
run_pwsh "PS: gh title mentioning -git and PowerShell (allowed — #2592)" \
  "gh issue create --title 'guardrails: block-dangerous-git.sh blocks PowerShell commands'" 0
# Intermediate path directory named Git is not a git invocation.
run_pwsh "PS: call-op to bash under Git\\bin (allowed — #2592, basename is bash)" \
  "& 'C:\\Program Files\\Git\\bin\\bash.exe' -c 'echo ok'" 0 # portability-ok: Windows path string in a test fixture, not a regex/sed construct
# Drive-relative git.exe (C:git.exe) must still count as git (Codex review on #2592).
run_pwsh "PS: drive-relative C:git.exe reset --hard (blocked — #2592)" \
  "& 'C:git.exe' --% reset --hard" 2
# Assignment RHS is a new pipeline without requiring whitespace — `$x=git …`
# must still count as command-position git (Claude review on #2592).
run_pwsh "PS: assignment without spaces \$x=git reset --hard (blocked)" "\$x=git reset --hard" 2

# Positive controls: the same scriptblock shape WITH a real git command still
# fails closed / blocks, so the narrowing did not open a bypass.
run_pwsh "PS: git reset --hard inside scriptblock (still fail-closed, #2592)" \
  "1..1 | ForEach-Object { git reset --hard }" 2
run_pwsh "PS: git clean -fd still blocked after command-position fix" \
  "git clean -fd" 2
run_pwsh "PS: git checkout . still blocked after command-position fix" \
  "git checkout ." 2

# Launcher-spelling parity (review round 4): the .exe-suffixed spellings of the
# covered launchers and the `start` alias of Start-Process are the same
# see-through surface — a spelling gap, not a new launcher class.
run_pwsh "PS: cmd.exe /c git reset --hard (fail-closed block)" \
  "cmd.exe /c git reset --hard" 2
run_pwsh "PS: powershell.exe -Command git reset --hard (fail-closed block)" \
  "powershell.exe -Command 'git reset --hard'" 2
run_pwsh "PS: start alias launches git (fail-closed block)" \
  "start git -ArgumentList 'reset --hard'" 2
run_pwsh "PS: start alias, no git (allowed)" "start notepad" 0
# A launcher whose program is a computed expression cannot be proven git-free.
run_pwsh "PS: Start-Process computed target (fail-closed block)" \
  "Start-Process ('g'+'it') -ArgumentList 'reset --hard'" 2
run_pwsh "PS: Start-Process -FilePath computed target (fail-closed block)" \
  "Start-Process -FilePath ('g'+'it') -ArgumentList 'reset --hard'" 2
# shellcheck disable=SC2016
run_pwsh "PS: launcher with variable target (fail-closed block)" \
  'saps $tool -ArgumentList "reset --hard"' 2

# Review round 6: quoted-string '@' is not a here-string opener; backslash
# path-qualified git normalizes for the tokenizer; separator-adjacent call
# operators are git-capable.
run_pwsh "PS: quoted '@' does not open a here-string (git line not swallowed)" \
  "$(printf "Write-Output '@'\ngit reset --hard\n'@'")" 2
run_pwsh "PS: backslash path-qualified git.exe (blocked)" \
  'C:\Git\cmd\git.exe reset --hard' 2
run_pwsh "PS: relative .\\git.exe (blocked)" \
  '.\git.exe reset --hard' 2
run_pwsh "PS: backslash path-qualified git.exe, safe op (allowed)" \
  'C:\Git\cmd\git.exe status' 0
run_pwsh "PS: semicolon-adjacent computed call (fail-closed block)" \
  "Write-Host ok;& ('g'+'it') reset --hard" 2

# Call-operator / dot-source of a CONSTANT target (#1968). `& "script.ps1"` is the
# ordinary PowerShell script-invocation idiom; the sink's git probe used to match
# any quote character after the operator, so a provably git-free literal path was
# blocked by a *git* guard. Per PowerShell about_Quoting_Rules a `$`-free
# double-quoted string and ANY single-quoted string are compile-time constants,
# so these are statically decidable as non-git.
run_pwsh "PS: call-op, double-quoted literal script path (allowed)" \
  '& "C:\tools\publish.ps1"' 0
run_pwsh "PS: call-op, single-quoted literal script path (allowed)" \
  "& 'C:\\tools\\publish.ps1'" 0
run_pwsh "PS: dot-source, double-quoted literal script path (allowed)" \
  '. "C:\tools\lib.ps1"' 0
run_pwsh "PS: dot-source, single-quoted literal script path (allowed)" \
  ". 'C:\\tools\\lib.ps1'" 0
# The fail-OPEN guard rail on that narrowing: an INTERPOLATING double-quoted
# target is computed and must still block, and a literal git command word is
# still caught by name because the git probe runs quote-intact.
# shellcheck disable=SC2016
run_pwsh "PS: call-op, interpolated variable target (fail-closed block)" \
  '& "$tool" reset --hard' 2
# shellcheck disable=SC2016
run_pwsh "PS: call-op, interpolated subexpression target (fail-closed block)" \
  '& "$(Get-Tool)" reset --hard' 2
# shellcheck disable=SC2016
run_pwsh "PS: call-op, interpolation inside a longer literal (fail-closed block)" \
  '& "C:\tools\$ver\thing.exe" reset --hard' 2
run_pwsh "PS: call-op, double-quoted literal git (blocked by name)" \
  '& "git" reset --hard' 2
run_pwsh "PS: call-op, single-quoted literal git (blocked by name)" \
  "& 'git' reset --hard" 2
run_pwsh "PS: call-op, quoted literal path whose basename is git (blocked by name)" \
  '& "C:\Git\cmd\git.exe" reset --hard' 2

# --- #2848: grouping + a bare-computed call target is not a git signal ----------
# Either factor alone was already allowed — a grouping construct by the #2592
# command-position fix above, a bare `& $tool` call target by the
# variable-command-word residual has_dynamic_invocation documents. Their
# CONJUNCTION still blocked, so ordinary PowerShell (resolve an interpreter into a
# variable behind a Test-Path fallback, then loop) was refused while the identical
# construct-free call was waved through. The bare-variable half no longer routes.
# shellcheck disable=SC2016
run_pwsh "PS: grouping + bare-computed target via Get-Command (allowed — #2848)" \
  '$py = "C:/tools/python.exe"; if (-not (Test-Path $py)) { $py = (Get-Command python).Source }; & $py C:/s/run.py --flag' 0
# shellcheck disable=SC2016
run_pwsh "PS: grouping + bare-computed target inside foreach (allowed — #2848)" \
  "\$ids = @('a','b'); foreach (\$id in \$ids) { & \$py \$script (Join-Path \$dir \"\$id.jsonl\") }" 0
# The one single-factor allowance that was previously unpinned: a grouping
# construct with a LITERAL call target. Pinned here so a future narrowing pass
# cannot regress it unnoticed.
# shellcheck disable=SC2016
run_pwsh "PS: grouping + literal call target (allowed — single-factor pin, #2848)" \
  "foreach (\$id in @('a','b')) { & \"C:/tools/python.exe\" C:/s/run.py \$id }" 0
# Fail-OPEN guard rails on that narrowing. A SUBEXPRESSION target still fails
# closed with the same grouping present, on `&` and on `.`, because `('g'+'it')`
# assembles a name the quote-intact literal probe can never see. Every other sink
# arm — literal git command word, computed launcher, interpolating-string target —
# is untouched and must still block alongside the same grouping.
# shellcheck disable=SC2016
run_pwsh "PS: grouping + subexpression call target (fail-closed block — #2848)" \
  "foreach (\$x in @('a')) { & ('g'+'it') reset --hard }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + subexpression dot-source target (fail-closed block — #2848)" \
  "foreach (\$x in @('a')) { . ('g'+'it') reset --hard }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + literal git command word (still blocked by name)" \
  "foreach (\$x in @('a')) { git reset --hard }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + computed launcher (still blocked)" \
  "foreach (\$x in @('a')) { Start-Process \$tool -ArgumentList 'reset' }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + interpolating-string call target (still blocked)" \
  "foreach (\$x in @('a')) { & \"\$tool\" reset --hard }" 2

# --- #2662: fail-closed headlines must not assert a git command is present -----
# The sink is possibly-git (iex / computed call / computed launcher can fire with
# no git token). Assert the softened headline on both the no-git-token path and a
# genuine unparsable-git path.
pwsh_stderr() {
  (cd "$REPO_SHA1" && bash "$HOOK" <<<"$(pwsh_command_json_cwd "$1" "$REPO_SHA1")" 2>&1 >/dev/null)
}
# shellcheck disable=SC2016
iex_rc=0
# shellcheck disable=SC2016  # intentional literal $cmd in the PowerShell payload
iex_out="$(pwsh_stderr 'Invoke-Expression $cmd')" || iex_rc=$?
assert_exit "PS: iex with no git token still fail-closes (#2662)" 2 "$iex_rc"
assert_contains "PS msg #2662: iex headline omits 'git command' claim" \
  "$iex_out" "this PowerShell command cannot be parsed with confidence and could reach git"
assert_absent "PS msg #2662: iex headline does not claim a git command exists" \
  "$iex_out" "PowerShell 'git' command"
assert_absent "PS msg #2662: iex headline does not say 'PowerShell git command'" \
  "$iex_out" "PowerShell git command"
assert_contains "PS msg #2662: iex trigger still names dynamic invocation" \
  "$iex_out" "dynamic invocation"
stop_out="$(pwsh_stderr 'git --% reset --hard')"
assert_contains "PS msg #2662: genuine unparsable-git path keeps cannot-parse claim" \
  "$stop_out" "cannot be parsed with confidence"
assert_contains "PS msg #2662: genuine unparsable-git path names could-reach-git" \
  "$stop_out" "could reach git"

# --- #2664: sink-shape allow-list tokens narrow the PS fail-closed branch ------
# Distinct from destructive-form tokens so an existing allow value cannot silently
# open the sink. Matching shape allows; unrelated form token does not.
# shellcheck disable=SC2016
run_pwsh "PS #2664: sink-shape allow opens iex fail-closed (allowed)" \
  'Invoke-Expression $cmd' 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-dynamic-invocation
# shellcheck disable=SC2016
run_pwsh "PS #2664: unrelated form token does not open iex sink (still blocked)" \
  'Invoke-Expression $cmd' 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=reset-hard
# shellcheck disable=SC2016
run_pwsh "PS #2664: all seven form tokens still leave iex blocked" \
  'Invoke-Expression $cmd' 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force,push-lease-unsafe,reset-hard,clean-force,checkout-dot,restore-dot,checkout-force
run_pwsh "PS #2664: sink-shape allow for special-construct opens --% path" \
  "git --% reset --hard" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-special-construct
run_pwsh "PS #2664: wrong sink-shape token does not open --% path (still blocked)" \
  "git --% reset --hard" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-dynamic-invocation
# Parsed dangerous forms still need their own tokens — sink-shape allow is not a
# backdoor for reset --hard once the command IS tokenizable.
run_pwsh "PS #2664: sink-shape allow does not waive a parsable reset --hard" \
  "git reset --hard" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-dynamic-invocation
# Allowing a sink shape must not fail-open independently visible siblings on the
# same compound command (Codex P1 on #2667).
run_pwsh "PS #2667: allowlisted iex does not waive visible reset --hard sibling" \
  "Invoke-Expression 'Write-Host harmless'; git reset --hard" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-dynamic-invocation
run_pwsh "PS #2667: allowlisted scriptblock does not waive visible reset --hard sibling" \
  "{ Write-Host hi }; git reset --hard" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-special-construct
run_pwsh "PS #2667: allowlisted launcher does not waive visible reset --hard sibling" \
  "Start-Process notepad; git reset --hard" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-launcher
# Both tokens: sink shape for iex + reset-hard for the visible sibling.
run_pwsh "PS #2667: sink allow + reset-hard allow opens iex;reset compound" \
  "Invoke-Expression 'Write-Host harmless'; git reset --hard" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-dynamic-invocation,reset-hard

malformed_rc=0
(cd "$REPO_SHA1" && bash "$HOOK" <<< 'not json at all' >/dev/null 2>&1) || malformed_rc=$?
assert_exit "malformed JSON payload (blocked)" 2 "$malformed_rc"

# --- A NUL in the payload must not void the guard (#2122) --------------------
# hook::jq_fields separates its fields with a NUL. A JSON NUL escape inside the
# command used to split that value in two, fail the helper's cardinality check
# and return non-zero — which this hook spells `|| exit 0`, a PreToolUse ALLOW
# with no diagnostic. Asserted at the HOOK boundary, not in the helper, because
# the boundary is where the bypass was observable.
#
# The rule is one line with no exceptions: a NUL in any field the hook reads
# BLOCKS, whatever the surrounding text says. That includes a command whose text
# is entirely NUL bytes, which strips to nothing and would otherwise be waved
# through by the empty-command skip, and a NUL in a command with nothing
# dangerous in it. The guard refuses rather than matching because the text it can
# read is not dependably the text that would run — stripping SPLICES the bytes
# either side of the NUL into a token the payload never carried contiguously —
# and which executor behaviour applies has not been traced.
#
# A NUL cannot live in a shell variable, so the payload is assembled inside jq:
# `[0] | implode` is the one-character NUL string, which jq re-emits as a NUL
# escape on the wire — the form the harness would deliver.
run_nul() {
  local label="$1" head="$2" tail="$3" expected="$4" rc
  (cd "$REPO_SHA1" && bash "$HOOK" <<<"$(jq -n --arg h "$head" --arg t "$tail" \
    '{tool_name:"Bash",tool_input:{command:($h + ([0] | implode) + $t)}}')" >/dev/null 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_nul "NUL after --hard (blocked)" "git reset --hard" "" 2
run_nul "NUL splitting the flag itself (blocked)" "git reset --ha" "rd" 2
run_nul "NUL then junk (blocked)" "git reset --hard" "x" 2
run_nul "leading NUL, text preserved (blocked)" "" "git reset --hard" 2
run_nul "all-NUL command strips to empty (blocked)" "" "" 2
run_nul "NUL in an otherwise harmless command (blocked)" "git status" "; echo bye" 2

# The block has to say what is wrong and what to do about it, not just refuse.
#
# Asserted HERE as well as in block-no-verify.test.sh, and the duplication is the
# point: both guards emit the same three lines by design, so a message edited in
# one and not the other is exactly the drift neither file would otherwise catch.
# Exit-code-only coverage cannot see it — the verdict is identical either way.
nul_stderr() {
  bash "$HOOK" <<<"$(jq -n --arg h "$1" --arg t "$2" \
    '{tool_name:"Bash",tool_input:{command:($h + ([0] | implode) + $t)}}')" 2>&1 >/dev/null
}
assert_contains "NUL msg: names the byte" "$(nul_stderr 'git reset --hard' 'x')" "NUL byte"
assert_contains "NUL msg: gives the fix" "$(nul_stderr 'git reset --hard' 'x')" \
  "reissue the tool call without the embedded NUL"

# The all-NUL command reaches the flag BEFORE the empty-COMMAND skip — its block
# must carry the NUL reason, and an empty command with no NUL must still take
# that skip. The pair is what pins the ordering; either row alone is equally
# consistent with a guard that refuses every empty command or blocks for some
# other reason.
assert_contains "NUL msg: all-NUL command refused by the flag, not skipped" \
  "$(nul_stderr '' '')" "NUL byte"
run "empty command, no NUL (allowed)" "" 0

report
