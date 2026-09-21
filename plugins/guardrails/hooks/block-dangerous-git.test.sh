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

GUARD_UNDER_TEST="$HOOK"

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
  local dir="$1"
  shift
  run_split "$dir" "$dir" "$@"
}

# run_split <payload-cwd> <process-cwd> <label> <command> <expected-exit> [env ...]
# The two directories DIVERGE, which is the shape #2124 was reported in: the hook
# process sits at the session root while the tool call runs elsewhere.
run_split() {
  local pcwd="$1" proc="$2" label="$3" command="$4" expected="$5"
  shift 5
  expect "$label" "$expected" --command "$command" --cwd "$pcwd" --chdir "$proc" -- "$@"
}

# run_nocwd <process-cwd> <label> <command> <expected-exit> [env ...]
# A payload carrying NO cwd field, for the lower rungs of the base chain.
run_nocwd() {
  local proc="$1" label="$2" command="$3" expected="$4"
  shift 4
  expect "$label" "$expected" --command "$command" --chdir "$proc" -- "$@"
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
  guard_invoke --command "$command" --cwd "$dir" --chdir "$dir" -- "$@"
  assert_exit "$label" "$expected" "$GUARD_RC"
  printf '%s' "$GUARD_ERR"
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
run_pwsh() {
  local label="$1" command="$2" expected="$3"
  shift 3
  expect "$label" "$expected" --tool PowerShell --command "$command" \
    --cwd "$REPO_SHA1" --chdir "$REPO_SHA1" -- "$@"
}
# The tool name is the third jq field. A payload MISSING cwd must still read it
# from the right slot, or a PowerShell command
# would silently be classified as Bash and the PowerShell-specific fail-closed
# sinks would never fire.
run_pwsh_nocwd() {
  local label="$1" command="$2" expected="$3"
  expect "$label" "$expected" --tool PowerShell --command "$command" --chdir "$REPO_SHA1"
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
# Single-factor pin: grouping with a LITERAL call target (#2848), so a future
# narrowing pass cannot regress it unnoticed.
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
# The DOLLAR spelling of that same subexpression target. `$( … )` and `( … )` are
# one construct, so the git lane must refuse both by shape; recognizing only the
# paren spelling left `& $($g) reset --hard` ALLOWED while `& ($g) reset --hard`
# blocked (#2924). Paired with its twin so the two cannot drift apart.
# shellcheck disable=SC2016
run_pwsh "PS: \$() subexpression call target (fail-closed block — #2924)" \
  "& \$(\$g) reset --hard" 2
# shellcheck disable=SC2016
run_pwsh "PS: paren twin of the row above (fail-closed block, unchanged)" \
  "& (\$g) reset --hard" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$() subexpression dot-source target (fail-closed block — #2924)" \
  ". \$('g'+'it') reset --hard" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + \$() subexpression call target (fail-closed block — #2924)" \
  "foreach (\$x in @('a')) { & \$('g'+'it') reset --hard }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + literal git command word (still blocked by name)" \
  "foreach (\$x in @('a')) { git reset --hard }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + computed launcher (still blocked)" \
  "foreach (\$x in @('a')) { Start-Process \$tool -ArgumentList 'reset' }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + interpolating-string call target (still blocked)" \
  "foreach (\$x in @('a')) { & \"\$tool\" reset --hard }" 2

# --- PowerShell token separators bash does not honor (#2928) ----------------
# PowerShell's tokenizer treats U+00A0 as token-separating whitespace; bash's
# `[[:space:]]` does not, so a destructive form spelled with one fell outside
# every boundary this guard measures. Normalized to an ASCII space at intake.
# Built from a BYTE ESCAPE, never pasted literally — a formatter that normalized
# a raw U+00A0 to a plain space would leave a case that passes while pinning
# nothing.
PS_NBSP=$'\xc2\xa0' # U+00A0 NO-BREAK SPACE
run_pwsh "PS: U+00A0 between --force and its remote (blocked — #2928)" \
  "git push --force${PS_NBSP}origin main" 2
run_pwsh "PS: U+00A0 between git and its subcommand (blocked — #2928)" \
  "git${PS_NBSP}reset --hard" 2
# The normalization changes where token boundaries fall, not what counts as
# destructive: read-only git stays allowed.
run_pwsh "PS: U+00A0 inside a read-only git command (allowed — #2928)" \
  "git log --oneline${PS_NBSP}-n 5" 0

# --- Unspaced assignment before a computed launcher (#2928) -----------------
# `ps::might_invoke_git`'s launcher class lacked `=`, so dropping the spaces
# around an assignment hid a launcher whose program is assembled at run time and
# could be git. The spaced form already failed closed; these bring the two level.
# The allow rows are the other direction of the same edit: widening a class that
# gates a FAIL-CLOSED sink is the over-block direction, so an ordinary
# assignment-of-a-launcher with a bare-variable program must stay allowed.
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before a computed launcher (fail-closed block — #2928)" \
  "\$p=Start-Process ('g'+'it') reset" 2
# shellcheck disable=SC2016
run_pwsh "PS: spaced assignment before a computed launcher (fail-closed block — pre-existing)" \
  "\$p = Start-Process ('g'+'it') reset" 2

# --- Unspaced assignment before a LAUNCHER: sink-trigger half (#2984) --------
# `ps::has_launcher` is the SINK TRIGGER; `ps::might_invoke_git`'s own launcher
# class (widened by #2928) is a MEASURING probe one layer down. #2928 widened the
# measuring class only, so the two rows below were pinned rc=0 by that PR — but
# that 0 was STRUCTURAL, not a decision: the sink was never entered, so no arm
# ever ran. Entry NARROWER than measurement is the mirror image of #2922/#2924,
# and it fails OPEN.
#
# That the 0 was an accident of entry, not a policy, is settled by measuring the
# SIBLING SPELLINGS of the identical class on the pre-fix base `fdbc42137`. Every
# one of them ALREADY blocked 0/2/2 there; only the unspaced `=` did not:
#
#   pwsh $script          2   (bare, start of string)
#   cmd $t                2
#   Start-Process $app    2
#   $a=1;pwsh $script     2   (`;` separator)
#   $a|pwsh $script       2   (`|` separator)
#   $out = pwsh $script   2   (SPACED `=`)
#   $out=pwsh $script     0   <- the lone hole
#
# So these rows now pin 2, matching all six siblings. This is the fail-CLOSED
# direction and weakens nothing; the ordinary-assignment guards below prove the
# widening is narrow rather than a blanket hit on assignment idiom.
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before a bare-variable launcher (fail-closed block — #2984)" \
  "\$out=pwsh \$script" 2
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before cmd of a variable (fail-closed block — #2984)" \
  "\$x=cmd \$t" 2
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before Start-Process of a variable (fail-closed block — #2984)" \
  "\$p=Start-Process \$app" 2
# The spaced contrasts, pinned so a future NARROWING of the class cannot silently
# re-open the hole from the other side.
# shellcheck disable=SC2016
run_pwsh "PS: spaced assignment before a bare-variable launcher (fail-closed block — pre-existing)" \
  "\$out = pwsh \$script" 2
# shellcheck disable=SC2016
run_pwsh "PS: semicolon-separated bare-variable launcher (fail-closed block — pre-existing sibling)" \
  "\$a=1;pwsh \$script" 2

# --- Unspaced assignment before a DYNAMIC INVOCATION: sink-trigger half (#2984)
# `ps::has_dynamic_invocation` matches a call `&` / dot-source `.` of a STRING
# LITERAL. Its separator class lacked `=` too, so `$a=& "$tool" commit` never
# entered the sink while the identical spaced form blocked.
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before a call of an interpolating string (fail-closed block — #2984)" \
  "\$a=& \"\$tool\" reset --hard" 2
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before a call of a single-quoted string (fail-closed block — #2984)" \
  "\$a=& 'git reset --hard'" 2
# shellcheck disable=SC2016
run_pwsh "PS: spaced assignment before a call of an interpolating string (fail-closed block — pre-existing)" \
  "\$a = & \"\$tool\" reset --hard" 2

# --- The widening is NARROW: ordinary assignment idiom stays allowed (#2984) --
# A `=` in the separator class admits an assignment whose RHS is a launcher or a
# string-literal call — NOT assignment generally. These are the allow side of the
# same edit and are pinned so a future widening cannot silently over-block them.
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment of a plain cmdlet (allowed — #2984 guard)" \
  "\$a=Get-Content f.txt" 0
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment of an env var to itself (allowed — #2984 guard)" \
  "\$env:PATH=\$env:PATH" 0
# `=` is the PowerShell assignment operator (about_Assignment_Operators), not a
# generic token separator. git(1) `-c <name>=<value>` is a config override
# (`git -c section.key=cmd …`): the value may spell a launcher word, but the
# `=` is not `$name=` and must not classify as a launcher assignment.
run_pwsh "PS: launcher token as a git -c config VALUE (allowed — not an assignment)" \
  "git -c core.pager=cmd log --oneline -n 1" 0
run_pwsh "PS: git -c section.key=cmd is not a launcher assignment (allowed)" \
  "git -c section.key=cmd log --oneline -n 1" 0
run_pwsh "PS: non-launcher git -c config value (allowed — #2984 guard)" \
  "git -c core.pager=cat log --oneline -n 1" 0
run_pwsh "PS: plain read-only git is untouched (allowed — #2984 guard)" \
  "git log --oneline -n 5" 0
# A `=`-glued launcher TOKEN with no `$name=` LHS is not an assignment, so the
# launcher sink is not entered. No git token either, so the parse path allows.
run_pwsh "PS: =-glued launcher token with no assignment LHS (allowed — #2984 guard)" \
  "Write-Output x=cmd y" 0
# Quoted text is a literal string (about_Quoting_Rules). An `=` inside quotes
# is data, even when it spells `=pwsh` or `& "…"` — it must not trip the sink.
# shellcheck disable=SC2016
run_pwsh "PS: equals inside double-quoted text does not trip launcher sink (allowed)" \
  'Write-Host "shell=pwsh $script"' 0
# shellcheck disable=SC2016
run_pwsh "PS: equals inside single-quoted text does not trip dynamic-invocation sink (allowed)" \
  'Write-Host '"'"'pattern=& "$tool"'"'"'' 0
# shellcheck disable=SC2016
run_pwsh "PS: quoted \$out=pwsh is data, not an assignment (allowed)" \
  'Write-Host '"'"'$out=pwsh $script'"'"'' 0
# The assignment-shaped call inside quotes is what actually reaches
# has_dynamic_invocation's quote-blanked confirmation. `pattern=&` has no
# `$name=` LHS and fails the structural check even unquoted. `$a` glued to
# the opening quote also fails the quote-intact predecessor class (no
# space/`;`/`{`/`}`/`(`/`|`/`&` before `$`). The confirmation arm needs
# `$name=` after one of those predecessors WHILE still inside a quoted
# span, so blanking erases it.
# shellcheck disable=SC2016
run_pwsh "PS: quoted \$a=& \"\$tool\" is data, not a string-literal call (allowed)" \
  'Write-Host '"'"'$a=& "$tool" reset --hard'"'"'' 0
# shellcheck disable=SC2016
run_pwsh "PS: quoted semicolon-then-\$a=& reaches blanking confirmation (allowed)" \
  'Write-Host "x; $a=& '"'"'ls'"'"'"' 0
# A dot-source separator is `.` followed by a QUOTE. A decimal literal and a
# property access after `=` carry no quote, so neither trips the assignment arm.
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment of a decimal literal (allowed — #2984 guard)" \
  "\$x=.5" 0

# Direct classification pins — hook rc=0 can hide "entered the sink and then
# allowed as git-free". These assert the trigger itself.
# shellcheck source=../lib/powershell/ps-command.sh
source "$HOOK_DIR/../lib/powershell/ps-command.sh"
pin_sink_trigger() {
  local label="$1" cmd="$2" expect="$3"
  PS_SINK_TRIGGER=""
  ps::classify_git_command PowerShell "$cmd" >/dev/null
  if [[ "$PS_SINK_TRIGGER" == "$expect" ]]; then
    ok "$label (trigger=${PS_SINK_TRIGGER:-none})"
  else
    bad "$label: expected trigger '${expect:-none}', got '${PS_SINK_TRIGGER:-none}'"
  fi
}
pin_predicate() {
  local label="$1" fn="$2" cmd="$3" expect="$4" rc=0
  "$fn" "$cmd" || rc=$?
  if [[ "$rc" == "$expect" ]]; then
    ok "$label (rc=$rc)"
  else
    bad "$label: $fn expected $expect, got $rc"
  fi
}
# shellcheck disable=SC2016
pin_predicate "ps::has_launcher: quoted shell=pwsh is not a launcher" \
  ps::has_launcher 'Write-Host "shell=pwsh $script"' 1
# shellcheck disable=SC2016
pin_predicate "ps::has_dynamic_invocation: quoted pattern=& \"\$tool\" is not a call" \
  ps::has_dynamic_invocation 'Write-Host '"'"'pattern=& "$tool"'"'"'' 1
# shellcheck disable=SC2016
pin_predicate "ps::has_dynamic_invocation: quoted \$a=& \"\$tool\" is not a call" \
  ps::has_dynamic_invocation 'Write-Host '"'"'$a=& "$tool" reset --hard'"'"'' 1
# shellcheck disable=SC2016
pin_predicate "ps::has_dynamic_invocation: quoted semicolon-then-\$a=& is not a call" \
  ps::has_dynamic_invocation 'Write-Host "x; $a=& '"'"'ls'"'"'"' 1
pin_predicate "ps::has_launcher: git -c section.key=cmd is not a launcher assignment" \
  ps::has_launcher 'git -c section.key=cmd log --oneline -n 1' 1
# shellcheck disable=SC2016
pin_predicate "ps::has_launcher: \$out=pwsh \$script still is a launcher assignment" \
  ps::has_launcher '$out=pwsh $script' 0
# shellcheck disable=SC2016
pin_predicate "ps::has_dynamic_invocation: \$a=& \"\$tool\" still is a string-literal call" \
  ps::has_dynamic_invocation '$a=& "$tool" reset --hard' 0
# shellcheck disable=SC2016
pin_sink_trigger "classify: quoted =pwsh does not enter launcher sink" \
  'Write-Host "shell=pwsh $script"' ""
# shellcheck disable=SC2016
pin_sink_trigger "classify: quoted \$a=& \"\$tool\" does not enter dynamic-invocation sink" \
  'Write-Host '"'"'$a=& "$tool" reset --hard'"'"'' ""
# shellcheck disable=SC2016
pin_sink_trigger "classify: quoted semicolon-then-\$a=& does not enter dynamic-invocation sink" \
  'Write-Host "x; $a=& '"'"'ls'"'"'"' ""
pin_sink_trigger "classify: git -c section.key=cmd does not enter launcher sink" \
  'git -c section.key=cmd log --oneline -n 1' ""
# shellcheck disable=SC2016
pin_sink_trigger "classify: \$out=pwsh \$script still enters launcher sink" \
  '$out=pwsh $script' "launcher"

# --- A `_to` helper assigns the CALLER's variable, never its own local --------
# `printf -v` walks bash's dynamic scope outward, so a helper whose own locals
# share a name with the destination the caller passed assigns that local and
# leaves the caller's variable untouched: a silent wrong answer rather than an
# error. `out` is this library's dominant accumulator name, so it is the
# destination a future caller is most likely to pass. The reference call names a
# variable no helper declares, so the two results have to agree.
ps_shadow_probe() {
  local out="shadowed"
  "$1" out "$2"
  printf '%s' "$out"
}
# shellcheck disable=SC2016
ps_shadow_input='x ${a`}b} ("y") w; q'
for ps_shadow_fn in ps::blank_quoted_spans_to ps::fold_escaped_brace_closers_to \
  ps::call_site_operand_region_to ps::blank_bracket_interiors_to; do
  "$ps_shadow_fn" ps_shadow_ref "$ps_shadow_input"
  # shellcheck disable=SC2154  # assigned indirectly, by the helper's `printf -v`
  assert_eq "$ps_shadow_fn assigns the caller's out, not its own local" \
    "$ps_shadow_ref" "$(ps_shadow_probe "$ps_shadow_fn" "$ps_shadow_input")"
done

# --- #2662: fail-closed headlines must not assert a git command is present -----
# The sink is possibly-git (iex / computed call / computed launcher can fire with
# no git token). Assert the softened headline on both the no-git-token path and a
# genuine unparsable-git path.
# The hook's exit code is the function's, so a caller can still take it with
# `out="$(pwsh_stderr …)" || rc=$?`.
pwsh_stderr() {
  guard_invoke --tool PowerShell --command "$1" --cwd "$REPO_SHA1" --chdir "$REPO_SHA1"
  printf '%s' "$GUARD_ERR"
  return "$GUARD_RC"
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

# --- a quoted git literal in COMPARISON-OPERAND position is data --------------
# ps::might_invoke_git exempts a quoted literal whose nearest preceding token is a
# comparison operator, but only in a command that carries no way to execute a
# computed value. Read-only pipelines that merely NAME git now pass the sink; a
# command that could turn the compared string back into a command word does not.
run_pwsh "PS cmp: -eq 'git' in a script block is data (allowed)" \
  "Get-Process | Where-Object { \$_.Name -eq 'git' }" 0
run_pwsh "PS cmp: -in @('git.exe','bash.exe') is data (allowed)" \
  "Get-CimInstance Win32_Process | Where-Object { \$_.Name -in @('git.exe','bash.exe') } | Select-Object ProcessId" 0
run_pwsh "PS cmp: case-prefixed -ceq 'git' is data (allowed)" \
  "Get-Process | Where-Object { \$_.Name -ceq 'git' } | Select-Object Id" 0
run_pwsh "PS cmp: -notin list element is data (allowed)" \
  "Get-Process | ? { \$_.Name -notin @('git','node') }" 0
run_pwsh "PS cmp: -like 'git*' is data (allowed)" \
  "Get-Process | ? { \$_.Name -like 'git*' }" 0
run_pwsh "PS cmp: -match \"^git\\.exe\$\" is data (allowed)" \
  "Get-Process | ? { \$_.Name -match \"^git\\.exe\$\" } | Select-Object Id" 0
# Rows the class already allowed — the exemption must not disturb them.
run_pwsh "PS cmp: no git token at all (allowed)" \
  "Get-ChildItem | Where-Object { \$_.Length -gt 0 }" 0
run_pwsh "PS cmp: Get-Process git as an argument (allowed)" \
  "Get-Process git | Select-Object Id" 0
run_pwsh "PS cmp: GitHub path component is not a git command (allowed)" \
  "Get-ChildItem C:\\code\\proj | Where-Object { \$_.PSIsContainer }" 0

# Counterexamples: every one keeps the quote-intact probe and stays blocked.
run_pwsh "PS cmp: bare git in call position beside a comparison (blocked)" \
  "git status; Get-Process | Where-Object { \$_.Name -eq 'node' }" 2
run_pwsh "PS cmp: Start-Process 'git' is a call target, not an operand (blocked)" \
  "Start-Process 'git' reset --hard; Get-Process | Where-Object { \$_.Name -eq 'x' }" 2
run_pwsh "PS cmp: saps 'git' is a call target, not an operand (blocked)" \
  "saps 'git' -ArgumentList 'push -f' | % { \$_ }" 2
run_pwsh "PS cmp: cmd /c 'git push --force' is a nested shell (blocked)" \
  "cmd /c 'git push --force' ; Get-Process | ? { \$_.Name -eq 'node' }" 2
run_pwsh "PS cmp: computed call of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { & \$_.Name push -f }" 2
run_pwsh "PS cmp: dot-source of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { . \$_.Name push -f }" 2
run_pwsh "PS cmp: iex of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { iex \$_.Name }" 2
run_pwsh "PS cmp: assignment is not a comparison operator (blocked)" \
  "\$n = 'git'; & \$n push -f | % { \$_ }" 2
run_pwsh "PS cmp: pipeline input is not an operand (blocked)" \
  "'git' | % { & \$_ push -f }" 2
run_pwsh "PS cmp: cmd /c of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { cmd /c \$_.Name push -f }" 2
run_pwsh "PS cmp: bash -c of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { bash -c \$_.Name }" 2
run_pwsh "PS cmp: quoted launcher calling the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { & 'bash' -c \$_.Name }" 2
run_pwsh "PS cmp: path-shaped call of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { & .\\\$_.Name push -f }" 2
run_pwsh "PS cmp: Invoke-Command around the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { Invoke-Command -ScriptBlock { & \$_.Name } }" 2
# Executors an enumeration cannot converge on. Each of these reaches a program
# without a call operator, an evaluator or a shell word, and each is refused by
# the read-only-cmdlet allowlist rather than by being named — a .NET static
# member, the automatic InvokeCommand API, a run-time alias, a script block
# compiled from the value, WMI/CIM process creation, a service binary path, a
# scheduled-task action, and any launcher that happens to be on PATH.
run_pwsh "PS cmp: [Diagnostics.Process]::Start of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { [Diagnostics.Process]::Start(\$_.Name,'push --force') }" 2
run_pwsh "PS cmp: InvokeCommand.InvokeScript of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { \$ExecutionContext.InvokeCommand.InvokeScript(\$_.Name) }" 2
run_pwsh "PS cmp: an alias minted from the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { Set-Alias zz \$_.Name }; zz push --force" 2
run_pwsh "PS cmp: a script block compiled from the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { \$sb=[scriptblock]::Create(\$_.Name); \$sb.Invoke() }" 2
run_pwsh "PS cmp: iwmi Win32_Process Create of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { iwmi -Class Win32_Process -Name Create -ArgumentList \$_.Name }" 2
run_pwsh "PS cmp: a service binary path from the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { nsv -Name z -BinaryPathName \$_.Name }" 2
run_pwsh "PS cmp: schtasks /tr of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { schtasks /create /tn z /sc once /st 00:00 /tr \$_.Name }" 2
run_pwsh "PS cmp: wmic process call create of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { wmic process call create \$_.Name }" 2
run_pwsh "PS cmp: a scheduled-task action from the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { New-ScheduledTaskAction -Execute \$_.Name }" 2
run_pwsh "PS cmp: npx of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { npx \$_.Name }" 2
run_pwsh "PS cmp: dotnet of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { dotnet \$_.Name }" 2
run_pwsh "PS cmp: cscript of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { cscript \$_.Name }" 2
run_pwsh "PS cmp: explorer of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { explorer \$_.Name }" 2
run_pwsh "PS cmp: ssh running the compared value on a remote host (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { ssh host \$_.Name push -f }" 2
# The same refusal covers the cmdlets that run a program with no call operator,
# no evaluator and no shell word.
run_pwsh "PS cmp: Invoke-Item of the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { Invoke-Item \$_.Name }" 2
run_pwsh "PS cmp: the ii alias of Invoke-Item (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { ii \$_.Name }" 2
run_pwsh "PS cmp: Start-Job around the compared value (blocked)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | % { Start-Job { \$_.Name } }" 2
run_pwsh "PS cmp: New-Object process construction beside a comparison (blocked)" \
  "New-Object System.Diagnostics.Process; Get-Process | ? { \$_.Name -eq 'git' }" 2
run_pwsh "PS cmp: call of a quoted git literal (blocked)" \
  "& 'git' commit --no-verify | % { \$_ }" 2
run_pwsh "PS cmp: quoted subcommand after a bare git (blocked)" \
  "git 'commit' | % { \$_ }" 2
# Right-hand operands only: a literal on the LEFT of the operator is ambiguous
# with a call target (`& 'git' -eq $x` invokes git), so it keeps the probe.
run_pwsh "PS cmp: left-hand literal keeps the quote-intact probe (blocked)" \
  "'git' -in \$names | % { \$_ }" 2
# The list walk is bounded; a list long enough to exhaust it fails closed.
run_pwsh "PS cmp: over-long operand list fails closed (blocked)" \
  "Get-Process | ? { \$_.Name -in @('a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','git') }" 2
# The sink message is the unchanged one — the exemption narrows what reaches the
# sink, it does not soften what the sink says.
cmp_out="$(pwsh_stderr "Get-Process | ? { \$_.Name -eq 'git' } | % { & \$_.Name push -f }")"
assert_contains "PS cmp: blocked counterexample still names could-reach-git" \
  "$cmp_out" "could reach git"

# Predicate pins — a hook rc of 0 can hide "entered the sink and was waved
# through by something else", so the mechanism itself is asserted.
pin_predicate "ps::might_invoke_git: -eq 'git' is data" \
  ps::might_invoke_git "Get-Process | Where-Object { \$_.Name -eq 'git' }" 1
pin_predicate "ps::might_invoke_git: -in @('git.exe','bash.exe') is data" \
  ps::might_invoke_git "Get-CimInstance Win32_Process | Where-Object { \$_.Name -in @('git.exe','bash.exe') } | Select-Object ProcessId" 1
pin_predicate "ps::might_invoke_git: -notin list element is data" \
  ps::might_invoke_git "Get-Process | ? { \$_.Name -notin @('git','node') }" 1
pin_predicate "ps::might_invoke_git: -match \"^git\\.exe\$\" is data" \
  ps::might_invoke_git "Get-Process | ? { \$_.Name -match \"^git\\.exe\$\" } | Select-Object Id" 1
pin_predicate "ps::might_invoke_git: computed call of the compared value still blocks" \
  ps::might_invoke_git "Get-Process | ? { \$_.Name -eq 'git' } | % { & \$_.Name push -f }" 0
pin_predicate "ps::might_invoke_git: bash -c of the compared value still blocks" \
  ps::might_invoke_git "Get-Process | ? { \$_.Name -eq 'git' } | % { bash -c \$_.Name }" 0
pin_predicate "ps::might_invoke_git: call of a quoted git literal still blocks" \
  ps::might_invoke_git "& 'git' commit --no-verify | % { \$_ }" 0
pin_predicate "ps::_is_readonly_cmdlet_pipeline: a comparison pipeline of interrogators is read-only" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | Where-Object { \$_.Name -eq 'git' }" 0
pin_predicate "ps::_is_readonly_cmdlet_pipeline: cmd at a command position refuses" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | ? { \$_.Name -eq 'git' } | % { cmd /c \$_.Name }" 1
pin_predicate "ps::_is_readonly_cmdlet_pipeline: an unrecognized command word refuses" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | ? { \$_.Name -eq 'git' } | % { npx \$_.Name }" 1
pin_predicate "ps::_is_readonly_cmdlet_pipeline: a type literal refuses" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | ? { \$_.Name -eq 'git' } | % { [Diagnostics.Process]::Start(\$_.Name) }" 1
pin_predicate "ps::_is_readonly_cmdlet_pipeline: a method call refuses" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | ? { \$_.Name -eq 'git' } | % { \$ExecutionContext.InvokeCommand.InvokeScript(\$_.Name) }" 1
pin_predicate "ps::_is_readonly_cmdlet_pipeline: a quoted launcher name is an argument, not a command word" \
  ps::_is_readonly_cmdlet_pipeline "Get-CimInstance Win32_Process | ? { \$_.Name -in @('git.exe','bash.exe') }" 0
pin_predicate "ps::_is_readonly_cmdlet_pipeline: a cmdlet argument is not a command word" \
  ps::_is_readonly_cmdlet_pipeline "Get-CimInstance Win32_Process | Select-Object ProcessId,Name" 0
pin_sink_trigger "classify: the comparison pipeline still enters the special-construct sink" \
  "Get-Process | Where-Object { \$_.Name -eq 'git' }" "special-construct"

# --- an EXPANDABLE operand is a command position, not data --------------------
# A double-quoted string is evaluated where it is written, so `"$( … )"` runs a
# program to build the value the comparison then reads. The walk replaces that
# span with an inert placeholder, which is precisely what hid the executor from
# the read-only-pipeline token scan: a security review reproduced the whole
# family through it. Every shape below therefore stays blocked, and the
# disqualifier is the `"` itself, not recognition of the executor inside it.
run_pwsh "PS cmp: expandable operand running cmd /c (blocked)" \
  "Write-Output (\"x\" -eq \"\$(cmd /c git push --force)\")" 2
run_pwsh "PS cmp: expandable operand in a Where-Object block (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(cmd /c git push --force)\" }" 2
run_pwsh "PS cmp: expandable operand running bash -c (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(bash -c 'git push --force')\" }" 2
run_pwsh "PS cmp: expandable operand running powershell -c (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(powershell -c 'git reset --hard')\" }" 2
run_pwsh "PS cmp: expandable operand running Start-Process (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(Start-Process git -ArgumentList push,--force)\" }" 2
run_pwsh "PS cmp: expandable operand calling a quoted git literal (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(& 'git' push -f)\" }" 2
run_pwsh "PS cmp: expandable operand starting a job (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(Start-Job { git push -f })\" }" 2
run_pwsh "PS cmp: expandable operand invoking git.exe (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(Invoke-Item git.exe)\" }" 2
run_pwsh "PS cmp: expandable operand constructing an object beside a git literal (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(New-Object System.Diagnostics.Process)\" -and \$_.Name -eq 'git' }" 2
run_pwsh "PS cmp: expandable operand running node beside a git literal (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(node -e 'x')\" -and \$_.Name -eq 'git' }" 2
run_pwsh "PS cmp: expandable operand interpolated into a -like pattern (blocked)" \
  "Get-Process | Where-Object { \$_.Name -like \"*\$(cmd /c git push -f)*\" }" 2
run_pwsh "PS cmp: expandable operand as a list element under -in (blocked)" \
  "Get-Process | Where-Object { \$_.Name -in @(\"\$(cmd /c git reset --hard)\",'git') }" 2
run_pwsh "PS cmp: expandable operand behind Get-Content and the ? alias (blocked)" \
  "Get-Content x.txt | ? { \$_ -eq \"\$(cmd /c git clean -fdx)\" }" 2
run_pwsh "PS cmp: expandable operand in a second Where-Object after an exempt one (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq 'git' } | Where-Object { \$_.Path -eq \"\$(cmd /c git push -f)\" }" 2
run_pwsh "PS cmp: expandable operand mixing a variable and a subexpression (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\${env:ComSpec} \$(cmd /c git push -f)\" }" 2
# Holes the executor-list gate left open too: the subexpression names git
# directly, or names an executor no list carried.
run_pwsh "PS cmp: expandable operand running git directly (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(git push --force)\" }" 2
run_pwsh "PS cmp: expandable operand scheduling a git task (blocked)" \
  "Get-Process | Where-Object { \$_.Name -eq \"\$(schtasks /create /tn x /tr 'git push -f' /sc once /st 00:00)\" }" 2
# A `@"` here-string is the OTHER expandable form, and it never reaches the
# exemption: its body is blanked at intake, so the git token is gone before the
# probe runs. The refusal therefore sits at the sink, where the blanking happened.
run_pwsh "PS cmp: expandable here-string operand (blocked)" \
  "$(printf '%s\n%s\n%s' "Get-Process | Where-Object { \$_.Name -eq @\"" "\$(cmd /c git push --force)" "\"@ }")" 2
# A VERBATIM here-string body carries no command position and is unchanged.
run_pwsh "PS cmp: verbatim here-string operand stays data (allowed)" \
  "$(printf '%s\n%s\n%s' "Get-Process | Where-Object { \$_.Name -eq @'" "git" "'@ }")" 0

# Predicate pins for the disqualifier itself. A hook rc of 2 can hide "blocked by
# something else entirely", so the gate is asserted directly, including the two
# cases a raw `"` scan and the opaque placeholder kind each get wrong.
pin_predicate "ps::_is_readonly_cmdlet_pipeline: an expandable operand refuses" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | Where-Object { \$_.Name -eq \"git\" }" 1
pin_predicate "ps::_is_readonly_cmdlet_pipeline: a verbatim operand still accepts" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | Where-Object { \$_.Name -eq 'git' }" 0
pin_predicate "ps::_is_readonly_cmdlet_pipeline: a double quote INSIDE a verbatim string is not an expandable string" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | Where-Object { \$_.Name -eq 'he said \"hi\"' }" 0
pin_predicate "ps::_is_readonly_cmdlet_pipeline: an apostrophe INSIDE an expandable string still refuses" \
  ps::_is_readonly_cmdlet_pipeline "Get-Process | Where-Object { \$_.Name -eq \"it's\" }" 1
pin_predicate "ps::might_invoke_git: an expandable operand is not data" \
  ps::might_invoke_git "Get-Process | Where-Object { \$_.Name -eq \"\$(cmd /c git push --force)\" }" 0
pin_sink_trigger "classify: the expandable here-string still enters the special-construct sink" \
  "$(printf '%s\n%s\n%s' "Get-Process | Where-Object { \$_.Name -eq @\"" "\$(cmd /c git push --force)" "\"@ }")" "special-construct"

# --- an expandable here-string BODY is itself a command position ----------------
# `ps::blank_herestrings` drops every body line before any sink trigger is
# tested, so a `$( … )` inside an expandable `@"` body was gone from the text the
# scans read: no trigger fired, the `((PS_HERESTRING_EXPANDABLE)) && return 2`
# refusal above was never reached, and the command was allowed. The DROP is what
# has to raise the trigger, because the dropped body is exactly where the command
# position lives. The gate is the literal `$(`, which over-approximates (a
# backtick-escaped `$(` is literal text to PowerShell), and over-approximating is
# the fail-closed direction.
ps_hs_body="$(printf '%s\n%s\n%s' "Write-Output @\"" "\$(git push --force)" "\"@")"
run_pwsh "PS hs: expandable body invoking git push --force (blocked)" "$ps_hs_body" 2
run_pwsh "PS hs: assignment form of the same body (blocked)" \
  "$(printf '%s\n%s\n%s' "\$x = @\"" "\$(git push --force)" "\"@")" 2
# Body lines are dropped one at a time, so the gate is per-line presence of `$(`:
# the subexpression opener and the git token may sit on different lines.
run_pwsh "PS hs: subexpression opener and git token on separate body lines (blocked)" \
  "$(printf '%s\n%s\n%s\n%s\n%s' "Write-Output @\"" "\$(" "git push --force" ")" "\"@")" 2
# Text after the column-zero closer is preserved, so the pipeline consumer stays
# visible. The body behind it must still refuse.
run_pwsh "PS hs: expandable body with a trailing pipeline after the closer (blocked)" \
  "$(printf '%s\n%s\n%s' "@\"" "\$(git push --force)" "\"@ | Out-File x.txt")" 2
# `hook::jq_fields` strips CR, so a CRLF payload reaches the classifier as LF-only
# text and has to reach the same verdict as its LF twin. Asserted at the HOOK
# boundary, which is the only place that stripping happens. The rc alone does not
# DISCRIMINATE: leave the CR in and the opener line no longer ends in `@"`, so the
# body stays in the text and its `(` trips special-construct, refusing for a
# different reason. The token case below pins WHICH trigger fired, and therefore
# that the stripping happened at all.
run_pwsh "PS hs: CRLF-line-ended copy of the same body (blocked)" \
  "$(printf '%s\r\n%s\r\n%s' "Write-Output @\"" "\$(git push --force)" "\"@")" 2
run_pwsh "PS hs: the CRLF copy is refused as a here-string body, not as a stray paren" \
  "$(printf '%s\r\n%s\r\n%s' "Write-Output @\"" "\$(git push --force)" "\"@")" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-subexpr
# Inner single quotes do not make a here-string body verbatim: PowerShell still
# expands `$( … )` inside them.
run_pwsh "PS hs: subexpression inside inner single quotes (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "'\$(git push --force)'" "\"@")" 2
# A read-only git subexpression is still text the Bash tokenizer never sees, so
# the read-only narrowing has nothing to narrow on.
run_pwsh "PS hs: read-only git subexpression in the body (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "\$(git status)" "\"@")" 2
# ACCEPTED OVER-BLOCKS, pinned so a later narrowing flips a case instead of
# passing silently. No git token appears in either command: the first carries a
# command position whose output the guard cannot read, and the second is a
# backtick escape that PowerShell treats as literal text. Modelling backtick
# escapes inside a dropped body is the parsing this library declines to do.
run_pwsh "PS hs: body whose only subexpression is non-git (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "Built \$(Get-Date)" "\"@")" 2
run_pwsh "PS hs: backtick-escaped subexpression in the body (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "\`\$(git push --force)" "\"@")" 2

# The regression fence. An expandable body with no `$(` carries no command
# position and a verbatim `@'` body carries none by construction, so none of
# these may move.
run_pwsh "PS hs: expandable body with variable interpolation only (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "Hello \$name" "\"@")" 0
run_pwsh "PS hs: expandable commit body with no command position (allowed)" \
  "$(printf '%s\n%s\n%s' "@\"" "fix: \$subject" "\"@ | git commit -F -")" 0
run_pwsh "PS hs: braced variable reference is not a subexpression (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "\${env:PATH}" "\"@")" 0
run_pwsh "PS hs: a \$ and a ( separated by a space are not \$( (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "cost is \$ (git)" "\"@")" 0
run_pwsh "PS hs: verbatim body naming git stays inert (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output @'" "git push --force" "'@")" 0
run_pwsh "PS hs: canonical verbatim commit form (allowed)" \
  "$(printf '%s\n%s\n%s' "@'" "fix: thing" "'@ | git commit -F -")" 0

# An rc of 0 cannot tell "never entered the sink" from "entered it and was waved
# through", so the trigger is pinned on both sides of the fence. The trigger is
# its OWN name rather than a reuse of special-construct: the allow token is
# derived from the trigger, and an operator who allowlisted `{}`/`--%` grouping
# would otherwise have silently allowlisted this class too, which would make the
# refusal a no-op for exactly the operators most likely to hit it.
pin_sink_trigger "classify: an expandable body carrying \$( enters the herestring-subexpr sink" \
  "$ps_hs_body" "herestring-subexpr"
pin_sink_trigger "classify: an expandable body with no command position enters no sink" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "Hello \$name" "\"@")" ""

# The trigger chain is ordered, and this arm is last, so a command that already
# had a special construct keeps reporting the construct it had. The #4188 pin
# above asserts that from the other side.
run_pwsh "PS hs: the special-construct token does not open the here-string body sink" \
  "$ps_hs_body" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-special-construct
# Its own token is the operator's explicit opt-in, and nothing else in the
# command is visible, so this one is allowed.
run_pwsh "PS hs: the herestring-subexpr token opens the expandable body" "$ps_hs_body" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-subexpr
# An allow token must not fail-open a plainly visible sibling. The
# special-construct region walk pairs the `"` of the `@"` opener with the `"` of
# the `"@` closer, so it cannot see inside a here-string at all: the new arm has
# to blank the here-string itself, or the caller's re-classification loop makes
# no progress, exhausts its four attempts and exits 0 with the sibling never
# checked (the invariant #2667 pinned).
run_pwsh "PS hs: an unrelated token does not open the sink at all (sibling never reached)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "\$(hi)" "\"@; git reset --hard")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-special-construct
run_pwsh "PS hs: the matching token does not waive a visible reset --hard sibling either" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "\$(hi)" "\"@; git reset --hard")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-subexpr
# ACCEPTED OVER-BLOCK: the operator opted out of launcher refusals, not out of
# this one. Blanking the launcher statement leaves the here-string, and the
# re-classification names it, so the command is refused under the trigger it now
# reports rather than the one it started with.
run_pwsh "PS hs: a launcher token does not carry over to the here-string body (blocked)" \
  "$(printf '%s\n%s\n%s' "pwsh -File build.ps1; Write-Output @\"" "Built \$(Get-Date)" "\"@")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-launcher
# The realistic casualty of the acceptance above: a commit body built with a
# subexpression. The remediation the guard already prints, a verbatim `@'` body
# piped to `git commit -F -`, is the way out.
run_pwsh "PS hs: commit body built with a subexpression (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "@\"" "fix: bump to \$(node -p 'x')" "\"@ | git commit -F -")" 2

# --- a here-string opener inside a `#` comment is not an opener -----------------
# PowerShell reads `Write-Output x # @"` as three tokens ending in a Comment, so
# the `@"` is comment TEXT and the following line is a live command. The opener
# scan never considered the `#`, so it opened a phantom here-string, dropped
# `git push --force` as body and let the column-zero `"@` close it: a balanced
# reduction with no sink trigger at all, allowed at rc 0. The spellings below put
# text after the closer, which is what makes them parse clean in pwsh; the bare
# three-line form is missing its terminator, so PowerShell would run none of it.
ps_hs_comment="$(printf '%s\n%s\n%s' "Write-Output x # @\"" "git push --force" "\"@ fine\"")"
run_pwsh "PS hs: an opener in a # comment tail leaves the next line visible (blocked)" \
  "$ps_hs_comment" 2
run_pwsh "PS hs: the @' spelling of the commented opener (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @'" "git push --force" "'@ fine'")" 2
# The bare three-line form, kept as a secondary pin. PowerShell refuses to run it
# ("the string is missing the terminator"), but the guard sees the same text and
# must reach the same verdict.
run_pwsh "PS hs: the unterminated spelling of the commented opener (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @\"" "git push --force" "\"@")" 2
# `hook::jq_fields` strips CR, so the CRLF payload reaches the classifier as its
# LF twin and has to reach the same verdict.
run_pwsh "PS hs: CRLF-line-ended copy of the commented opener (blocked)" \
  "$(printf '%s\r\n%s\r\n%s' "Write-Output x # @\"" "git push --force" "\"@ fine\"")" 2
# This guard owns destructive non-push forms too, and the recovered line is an
# ordinary command once it is no longer read as here-string body.
run_pwsh "PS hs: reset --hard recovered from behind a commented opener (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @\"" "git reset --hard" "\"@ fine\"")" 2
# The commit-guard shape. block-noncanonical-commit and block-convention-violation
# DEFER on a classifier rc 2, so this guard is where the refusal lands.
run_pwsh "PS hs: a git commit carrying a commented opener (blocked)" \
  "$(printf '%s\n%s\n%s' "git commit -m fix # @\"" "Write-Output done" "\"@ fine\"")" 2

# NO FLIP. The one-line form already blocked before this change, as a phantom
# UNBALANCED here-string. It must still block; only the trigger it reports moves.
run_pwsh "PS hs: a one-line commented opener beside a git command (blocked, unchanged)" \
  "git log --oneline # @\"" 2
# The rc does not move but the ATTRIBUTION does: this was a phantom
# `herestring-unbalanced`, whose arm blanks from the opener to end of input, so a
# standing token for that shape reduced it to a bare `git log` and allowed it.
pin_sink_trigger "classify: the one-line form now reports the unconfirmed opener, not unbalanced" \
  "git log --oneline # @\"" "herestring-opener-unconfirmed"
run_pwsh "PS hs: the unbalanced token no longer opens the one-line commented form" \
  "git log --oneline # @\"" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-unbalanced

# NO DE-ESCALATION for an EXPANDABLE opener. The lines are kept in view, but the
# here-string reading is still live, and under it they are an expandable body
# whose `$( … )` is a command position. A visible-text probe answers only "is a
# git token here", so it cannot stand in for that reading: an unconfirmed `"`
# opener takes the same unconditional refusal a confirmed one takes, and this
# git-FREE command blocks for the same reason its git-carrying twin does.
run_pwsh "PS hs: a git-free commented opener over an expandable-looking body (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @\"" "\$(whoami)" "\"@ fine\"")" 2
run_pwsh "PS hs: the git-carrying twin of the same shape (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @\"" "\$(cmd /c git push --force)" "\"@ fine\"")" 2

# FALSE-POSITIVE GUARDS. The `#` test runs on the quote-STRIPPED line, so a `#`
# that lives inside a string never refuses a real opener, and a real body is free
# to contain one.
run_pwsh "PS hs: a legitimate here-string whose body contains a # (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output @\"" "release # 1" "\"@")" 0
run_pwsh "PS hs: a # inside quotes before a real opener (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output 'x # y' @\"" "git push --force" "\"@")" 0
# The `'` in `don't` opens a span that owns everything through the `'` in `it's`,
# so the `#` sits INSIDE that span and is blanked with it: this stays a REAL
# here-string, which is what pwsh reads it as (Generic, Generic,
# HereStringExpandable, parse clean), and `git push --force` is inert body text.
# Pinned as expected-0 so a later change to the quote blanking cannot flip it
# silently.
run_pwsh "PS hs: apostrophes pairing across the # keep a real opener (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Host don't # it's @\"" "git push --force" "\"@")" 0
# ACCEPTED OVER-BLOCK, the cost of that pairing being the ordered span walk. The
# walk refuses to pair a DOUBLED-quote escape and emits the line verbatim, so the
# quotes survive and the opener is not confirmed; the `#` inside `'a''# b'`
# survives with them and would refuse it on its own too. PowerShell reads this as
# the string `a'# b` followed by a live opener, with the git line inert body; the
# guard refuses it.
run_pwsh "PS hs: a doubled-quote escape hiding a # refuses the opener (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output 'a''# b' @\"" "git push --force" "\"@")" 2
# THE OTHER DIRECTION, and the one a per-style strip gets wrong. An apostrophe
# INSIDE a double-quoted string is ordinary text to PowerShell, so the `#` these
# two apostrophes appear to straddle is a real comment start and the `@"` after it
# is comment TEXT. A single-quote strip run independently of the double-quote one
# pairs the apostrophe in `"it's"` with the one in `don't`, deletes the `#`
# between them, and the line reads as a clean opener, so the live `git push
# --force` below is then dropped as body. Both spellings parse clean in pwsh
# 7.6.6 with the git line live at top level.
run_pwsh "PS hs: an apostrophe inside a double-quoted string does not erase the # (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Host \"it's\" # don't \"x @\"" "git push --force" "\"@\"")" 2
run_pwsh "PS hs: the minimal apostrophe-straddle spelling of the same erasure (blocked)" \
  "$(printf '%s\n%s\n%s' "echo \"'\" # ' \" @\"" "git push --force" "\"@\"")" 2
run_pwsh "PS hs: the canonical verbatim commit form is untouched (allowed)" \
  "$(printf '%s\n%s\n%s' "@'" "fix: thing" "'@ | git commit -F -")" 0

# An rc of 0 cannot tell "never entered the sink" from "entered and waved
# through", and an rc of 2 cannot tell WHICH trigger refused, so both are pinned.
# The arm is LAST in the chain: a command that already carries a special construct
# keeps reporting the construct it carries. The construct has to sit BEFORE the
# `#` on that line, because ps::blank_quoted_spans_to pairs the comment's unpaired
# `"` with the next `"` in the command and erases everything between.
pin_sink_trigger "classify: a commented opener enters the herestring-opener-unconfirmed sink" \
  "$ps_hs_comment" "herestring-opener-unconfirmed"
pin_sink_trigger "classify: a special construct before the # still reports itself" \
  "$(printf '%s\n%s\n%s' "Write-Output (x) # @\"" "git push --force" "\"@ fine\"")" "special-construct"

# ALLOW-TOKEN CASES. The token narrows the sink SHAPE; it never waives a git line
# the reduction leaves plainly visible.
run_pwsh "PS hs: the opener-unconfirmed token does not waive the visible git push --force" \
  "$ps_hs_comment" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
# A commented opener ABOVE a real hanging opener. `herestring-unbalanced` is first
# in the chain and wins here, and its arm blanks from the hanging opener to end of
# input, so the shared helper is what keeps the commented line from being taken
# as that hanging opener and the live `git push --force` from being blanked with
# it.
ps_hs_dual="$(printf '%s\n%s\n%s\n%s' "Write-Output x # @\"" "git push --force" "@\"" "more")"
run_pwsh "PS hs: the unbalanced token does not blank a commented opener's live line" \
  "$ps_hs_dual" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-unbalanced
# This is the one fixture that raises BOTH flags, so it is the one that
# discriminates the new trigger's CHAIN PLACEMENT against its predecessor, and an
# rc of 2 alone cannot tell the two orderings apart. `herestring-unbalanced` is
# first and must stay first: it is the reading whose allow arm hides the most
# text, so reporting the comment opener here would hand this shape the narrower
# token.
pin_sink_trigger "classify: a commented opener above a real hanging opener still reports unbalanced" \
  "$ps_hs_dual" "herestring-unbalanced"
# A STACKED opener tail, in the spelling that actually re-forms: `# @"@'` strips
# to `# @"`, a commented opener again. The arm substitutes the inert placeholder
# for the two opener characters rather than stripping them, so the line cannot
# flag a second time. The caller's loop counts attempts and exits 0 when the
# budget runs out, so an arm that bought one pair per pass would fail OPEN with
# the git line never checked.
ps_hs_comment_stacked="$(printf '%s\n%s\n%s' "Write-Output x # @\"@'" "git push --force" "\"@ fine\"")"
pin_sink_trigger "classify: a stacked commented opener tail still reports the unconfirmed opener" \
  "$ps_hs_comment_stacked" "herestring-opener-unconfirmed"
run_pwsh "PS hs: a stacked commented opener tail settles in one pass (blocked)" \
  "$ps_hs_comment_stacked" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed

# --- a line whose quoting the walk REFUSED to pair confirms no opener ----------
# ps::blank_quoted_spans_to emits the rest of the line VERBATIM when it meets a
# DOUBLED quote (PowerShell's escape: `'it''s'`, `"say ""hi"""`), because the
# pairing is ambiguous. `Write-Host 'a''b @'` therefore comes out of the walk
# unchanged: it still ends in `@'` and carries no `#`, so a suffix test paired
# with a `#` test alone reads it as a real opener and the live command line under
# it goes as here-string body. pwsh 7.6.6 parses each payload below with zero
# errors and line 2 is a live top-level command in every one. An opener is
# confirmed only when NO quote survives the walk.
ps_hs_unpaired_sq="$(printf '%s\n%s\n%s' "Write-Host 'a''b @'" "git push --force" "'@ fine'")"
ps_hs_unpaired_dq="$(printf '%s\n%s\n%s' "Write-Host \"a\"\"b @\"" "git push --force" "\"@ fine\"")"
run_pwsh "PS hs: a doubled single quote before the opener tail (blocked)" \
  "$ps_hs_unpaired_sq" 2
run_pwsh "PS hs: the doubled double-quote spelling of the same shape (blocked)" \
  "$ps_hs_unpaired_dq" 2
# This guard owns destructive non-push forms too.
run_pwsh "PS hs: reset --hard recovered from behind an unpaired-quote tail (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Host 'a''b @'" "git reset --hard" "'@ fine'")" 2
# `hook::jq_fields` strips CR, so the CRLF payload reaches the classifier as its
# LF twin and has to reach the same verdict.
run_pwsh "PS hs: CRLF-line-ended copy of the unpaired-quote form (blocked)" \
  "$(printf '%s\r\n%s\r\n%s' "Write-Host 'a''b @'" "git push --force" "'@ fine'")" 2
# An rc of 2 cannot tell WHICH trigger refused, and the trigger fires for two
# distinct causes now, so the quoting cause is pinned on its own.
pin_sink_trigger "classify: an unconfirmable opener enters the herestring-opener-unconfirmed sink" \
  "$ps_hs_unpaired_sq" "herestring-opener-unconfirmed"
# The token narrows the sink SHAPE; it never waives a git line the reduction
# leaves plainly visible.
run_pwsh "PS hs: the opener-unconfirmed token does not waive the visible git push --force" \
  "$ps_hs_unpaired_sq" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
run_pwsh "PS hs: the same, in the doubled double-quote spelling" \
  "$ps_hs_unpaired_dq" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
# The arm replaces the line's opaque TAIL, not just the two opener characters.
# Taking only those two off leaves the surviving quote standing, and the Bash
# tokenizer this reduction is handed to pairs a single-quoted span ACROSS
# newlines, so the live git line below would be swallowed into one quoted word.
# A sibling statement standing BEFORE the ambiguity on the same line stays
# visible, which is the invariant #2667 pins.
run_pwsh "PS hs: a sibling before the ambiguity stays visible under the token" \
  "$(printf '%s\n%s\n%s' "git reset --hard; Write-Host 'a''b @'" "Write-Output body" "'@ fine'")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
# ACCEPTED OVER-BLOCK. `Write-Output 'a''b' @"` is a REAL here-string to
# PowerShell: the string `a'b`, then a live opener, with the git line as inert
# body. The walk refuses to pair the doubled quote, so a quote survives the line
# and the opener is not confirmed. Leaving text in view can only over-block.
run_pwsh "PS hs: a doubled-quote string before a real opener (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output 'a''b' @\"" "git push --force" "\"@")" 2
# rc 0 PINS FOR LEGITIMATE OPENERS. The walk DELETES a properly paired span, so
# no quote survives and the opener still confirms. Each body names git, so an
# unconfirmed reading would route to the sink and block on the git it can see:
# these pins discriminate rather than passing either way.
run_pwsh "PS hs: a paired double-quoted string before a real opener (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Host \"x\" @\"" "git push --force" "\"@")" 0
run_pwsh "PS hs: a paired single-quoted string before a real opener (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output 'a' @\"" "git push --force" "\"@")" 0
run_pwsh "PS hs: an apostrophe inside a paired double-quoted string (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"it's fine\" @\"" "git push --force" "\"@")" 0
run_pwsh "PS hs: a bare verbatim opener after git commit -m (allowed)" \
  "$(printf '%s\n%s\n%s' "git commit -m @'" "subject" "'@")" 0

# --- an UNCONFIRMED EXPANDABLE opener keeps the expandable-body refusal --------
# Keeping the lines in view is not a proof of git-freedom when the opener quote is
# `"`. PowerShell reads `Write-Output 'a''b' @"` as the string `a'b` followed by a
# LIVE opener (`'a''b'` is the doubled-quote escape), so the lines under it are an
# EXPANDABLE body and a `$( … )` in it is a COMMAND POSITION evaluated at
# construction time. Refusing to open the here-string leaves that body as visible
# text, and `ps::might_invoke_git` over visible text answers only "is a git token
# here".
#
# EVERY BODY BELOW SPELLS ITS CALL `& $g`, so no literal `git` token appears
# anywhere in the command. That is the whole point of these fixtures: the probe
# answers NO, and a fixture carrying a literal `git` would pass even with the bug
# present and pin nothing. An unconfirmed `"` opener therefore takes the same
# unconditional expandable-body refusal a CONFIRMED one takes.
run_pwsh "PS hs: an unconfirmed expandable opener over an obfuscated push --force (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output 'a''b' @\"" "\$(& \$g push --force)" "\"@")" 2
run_pwsh "PS hs: the doubled double-quote spelling of the same shape (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"a\"\"b\" @\"" "\$(& \$g push --force)" "\"@")" 2
# This guard owns destructive non-push forms too.
run_pwsh "PS hs: an obfuscated reset --hard in an unconfirmed expandable body (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output 'a''b' @\"" "\$(& \$g reset --hard HEAD~1)" "\"@")" 2
# `hook::jq_fields` strips CR, so the CRLF payload reaches the classifier as its
# LF twin and has to reach the same verdict.
run_pwsh "PS hs: CRLF-line-ended copy of the obfuscated expandable body (blocked)" \
  "$(printf '%s\r\n%s\r\n%s' "Write-Output 'a''b' @\"" "\$(& \$g push --force)" "\"@")" 2
# The OTHER cause of an unconfirmed opener, a `#` in front of the opener
# characters, carries the identical hole and takes the identical refusal. The
# quote is what decides, not which test refused to confirm.
run_pwsh "PS hs: the # cause of an unconfirmed expandable opener refuses too (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @\"" "\$(& \$g push --force)" "\"@ fine\"")" 2
# A VERBATIM `@'` unconfirmed opener is unaffected and must stay so: a `@'` body
# carries no command position at all, so nothing is suspended and the visible-text
# probe is the whole answer. Pinned at 0 with an obfuscated body, which is what
# discriminates the verbatim path from the expandable one.
run_pwsh "PS hs: an unconfirmed VERBATIM opener over the same body (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Host 'a''b @'" "\$(& \$g push --force)" "'@ fine'")" 0
# THE COST, pinned rather than left to be re-found. The refusal is by SHAPE, so
# an unconfirmed `"` opener blocks whatever its body holds, a git-free body
# carrying no `$(` at all included. Both are rc 0 on the base and rc 2 here, one
# per unconfirmed cause.
run_pwsh "PS hs: an unconfirmed expandable opener over a plain body (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output 'a''b' @\"" "hello" "\"@")" 2
run_pwsh "PS hs: the # cause over a plain body (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @\"" "hello" "\"@ fine\"")" 2

# --- a backslash before the quote: the walk pairs where the LEGACY one escapes --
# `Write-Output "\"a" @"` is a Generic, the string `"a`, and a LIVE `@"` opener;
# pwsh 7.6.6 parses it clean and the line under it executes. The walk ignores
# backslashes, so it pairs `"\"` and then `a" @"`, reducing the line to
# `Write-Output a` with no opener suffix at all. The LEGACY reduction reads `\"`
# as an escape inside `"([^"\\]|\\.)*"`, reduces to `Write-Output  @"`, and
# CONFIRMS an expandable opener. One reduction sees an opener and the other does
# not, so the line is UNCONFIRMED and takes the unconditional expandable refusal
# the base reaches by confirming and dropping the body.
#
# EVERY BODY BELOW SPELLS ITS CALL `& $g`, so no literal `git` token appears
# anywhere in the command. The literal-git twin of the first row is rc 2 on BOTH
# trees, pinned directly beneath it, so a fixture that spelled `git` out could not
# pin this class at all: it passes with the defect present.
run_pwsh "PS hs: a backslash-escaped quote before an opener the walk loses (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"\\\"a\" @\"" "\$(& \$g push --force)" "\"@\"")" 2
run_pwsh "PS hs: the literal-git twin of that shape (blocked on both trees)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"\\\"a\" @\"" "\$(git push --force)" "\"@\"")" 2
run_pwsh "PS hs: the no-space spelling of the backslash-escaped quote (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output a\"\\\"a\"@\"" "\$(& \$g push --force)" "\"@\"")" 2
run_pwsh "PS hs: a lone backslash-escaped quote before the opener (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"\\\" \"@\"" "\$(& \$g push --force)" "\"@\"")" 2
# `hook::jq_fields` strips CR, so the CRLF payload reaches the classifier as its
# LF twin and has to reach the same verdict.
run_pwsh "PS hs: CRLF-line-ended copy of the backslash-escaped opener (blocked)" \
  "$(printf '%s\r\n%s\r\n%s' "Write-Output \"\\\"a\" @\"" "\$(& \$g push --force)" "\"@\"")" 2
# THE COST of that refusal being by SHAPE, pinned rather than left to be re-found:
# the same opener blocks over a body that holds no command position at all, over
# one whose call sits outside any `$( )`, and over a lone-CR-terminated spelling
# that `hook::jq_fields` folds into a single line. All three are rc 0 on the base.
run_pwsh "PS hs: the backslash-escaped opener over a plain body (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"\\\"a\" @\"" "hello" "\"@\"")" 2
run_pwsh "PS hs: the backslash-escaped opener over a body with no subexpression (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"\\\"a\" @\"" "& \$g push --force" "\"@\"")" 2
run_pwsh "PS hs: the lone-CR-terminated spelling of the backslash-escaped opener (blocked)" \
  "$(printf '%s\r%s\r%s' "Write-Output \"\\\"a\" @\"" "\$(& \$g push --force)" "\"@\"")" 2
# THE OTHER DIRECTION of the same disagreement, and it is PRE-EXISTING on this
# branch rather than new with the quadrant rule: a prefix string ending in a
# BACKSLASH. `"([^"\\]|\\.)*"` runs the escape through to end of line and leaves
# the base no opener at all, while the walk pairs `"C:\p\"` and reads the `@"`
# after it, so this benign parse-clean here-string is base-no / walk-yes and is
# refused as unconfirmed. rc 0 on the base, rc 2 here.
run_pwsh "PS hs: a real here-string after a path ending in a backslash (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"C:\\p\\\" @\"" "hello" "\"@")" 2

# --- the allow arm must not leave an ORPHAN closer ----------------------------
# Neutralizing an unconfirmed opener line without its matching column-zero closer
# leaves that closer standing, and the downstream Bash tokenizer reads
# `"@\ngit push --force` as ONE unterminated quoted word: a plainly visible git
# line is then never checked. The token forgives the AMBIGUITY, never the git.
run_pwsh "PS hs: the token does not feed a visible git line to an orphan closer" \
  "$(printf '%s\n%s\n%s\n%s' "Write-Output 'a''b' @\"" "hello" "\"@" "git push --force")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
run_pwsh "PS hs: the verbatim spelling of the orphan closer (blocked under the token)" \
  "$(printf '%s\n%s\n%s\n%s' "Write-Host 'a''b @'" "hello" "'@" "git push --force")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
# ONLY THE TWO CLOSER CHARACTERS, so live code standing after the closer on that
# same line stays in view. The verbatim spelling is what discriminates this arm:
# a `'` opener raises no expandable refusal, so the rc comes from the reduction
# alone. rc 0 on the base, rc 2 here.
run_pwsh "PS hs: a destructive git after the neutralized closer stays visible" \
  "$(printf '%s\n%s\n%s' "Write-Host 'a''b @'" "hello" "'@; git reset --hard")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
# The rc 0 twin of that pin: the same shape with a git-free tail is still allowed,
# so the arm is not simply blocking everything it touches.
run_pwsh "PS hs: a git-free tail after the neutralized closer is still allowed" \
  "$(printf '%s\n%s\n%s' "Write-Host 'a''b @'" "hello" "'@; Write-Output done")" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
# A sibling standing BEFORE the ambiguity still reaches the checks, which is the
# visibility invariant #2667 pins: neutralizing the closer must not widen into
# hiding the prefix.
run_pwsh "PS hs: a sibling before the ambiguity still blocks past a neutralized closer" \
  "$(printf '%s\n%s\n%s' "git reset --hard; Write-Host 'a''b @'" "hello" "'@")" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed

# --- the walk may only ever REMOVE openers from the base's confirmed set -------
# PowerShell reads `<# … #>` as a block comment over the first three lines below,
# so the payload under it is an ordinary statement and it RUNS. Neither the base
# nor this change models block comments, so both read line 2 as a candidate
# opener; what differs is whether either CONFIRMS it. The base's ordered two-pass
# quote strip eats `'s" @'` out of `note "it's" @'` and is left with `note "it`,
# which ends in no opener, so the base keeps every line visible and the payload
# reaches a sink. The span walk pairs `"it's"` properly, deletes it, and reads the
# clean suffix of `note  @'` as a confirmed opener, which drops lines 3 and 4 as
# body and leaves nothing to refuse. Better pairing made MORE lines qualify as
# openers, and dropping body is the only way this classifier hides text from the
# later scans. An opener is confirmed only when the base's reduction confirms it
# too, so whatever this change drops the base dropped as well.
#
# EVERY PAYLOAD BELOW SPELLS ITS CALL `& ('g'+'it')`, so no literal `git` token
# appears in the command. That is load-bearing rather than cosmetic: the
# literal-`git` spelling of this shape is rc 0 on the base as well, because the
# reduction it emits hands the Bash tokenizer an unpaired `@'` that pairs across
# newlines and swallows the git line into one quoted word, so a fixture written
# that way cannot pin PARITY with the base: it pins the base at 0. It still
# discriminates this change, and it is pinned on its own below. The `( )`
# grouping is what the base's own special-construct sink refuses, and it is what
# makes these rows 2 on both trees.
ps_hs_block_apos="$(printf '%s\n%s\n%s\n%s\n%s' "<#" "note \"it's\" @'" "#>" "& ('g'+'it') push --force" "'@'")"
run_pwsh "PS hs: an opener the walk pairs but the legacy reduction does not (blocked)" \
  "$ps_hs_block_apos" 2
# An rc of 2 cannot say WHICH line the guard refused over, and the claim here is
# that the payload line stays VISIBLE rather than going as body. The trigger the
# base reports for this command is the pin that says so.
pin_sink_trigger "classify: the payload under the wrapper is visible, not body" \
  "$ps_hs_block_apos" "special-construct"
# A SIBLING after the closer. Under the phantom here-string reading the closer
# line is where the body ends, so a shape that gives the closer live trailing
# code is the one that could settle differently.
run_pwsh "PS hs: a sibling command after the closer of the same shape (blocked)" \
  "$(printf '%s\n%s\n%s\n%s\n%s' "<#" "note \"it's\" @'" "#>" "& ('g'+'it') push --force" "'@'; Write-Output done")" 2
# The same disagreement without an English apostrophe: any single `'` inside a
# properly paired double-quoted span puts the two reductions at odds.
run_pwsh "PS hs: the \"a'b\" spelling of the same disagreement (blocked)" \
  "$(printf '%s\n%s\n%s\n%s\n%s' "<#" "note \"a'b\" @'" "#>" "& ('g'+'it') push --force" "'@'")" 2
# `hook::jq_fields` strips CR, so the CRLF payload reaches the classifier as its
# LF twin and has to reach the same verdict.
run_pwsh "PS hs: CRLF-line-ended copy of the walk-paired opener (blocked)" \
  "$(printf '%s\r\n%s\r\n%s\r\n%s\r\n%s' "<#" "note \"it's\" @'" "#>" "& ('g'+'it') push --force" "'@'")" 2
# The token narrows the sink SHAPE; it never waives the grouping the recovered
# line carries. This is also the first shape whose unconfirmed opener line the
# walk reduces CLEANLY, so it is the first to reach the neutralizing arm with no
# surviving quote before the opener characters.
run_pwsh "PS hs: the opener-unconfirmed token does not waive the recovered grouping" \
  "$ps_hs_block_apos" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=ps-unparsable-herestring-opener-unconfirmed
# The literal-`git` spelling named above, pinned here rather than left unpinned.
# It is rc 0 on the base: nothing routes it to a sink, and the base's own parse
# hands the Bash tokenizer an unpaired `@'` that pairs across newlines and
# swallows the git line into one quoted word. It is rc 2 here because the
# unconfirmed opener routes the command to the sink, whose possibly-git gate is a
# plain token scan that does see the token. A shape this change blocks and its
# base does not is the fail-closed direction the quadrant rule leaves open.
run_pwsh "PS hs: the literal-git spelling of the walk-paired opener (blocked)" \
  "$(printf '%s\n%s\n%s\n%s\n%s' "<#" "note \"it's\" @'" "#>" "git push --force" "'@'")" 2
# The EXPANDABLE spelling of the same disagreement, which is the one that reaches
# PS_HERESTRING_UNCONFIRMED_EXPANDABLE through this cause. `note "a'b" 'c' @"`
# walks clean (both spans pair and are deleted), while the base's single-quote
# pass spans `'b" '` and its double-quote pass then eats what is left, so the base
# sees no opener. The body names no literal `git`, so the refusal comes from the
# unconditional expandable-body path rather than from a visible-text hit: under
# the here-string reading those lines are an expandable body and the `$( … )` in
# them is a command position. rc 0 on the base, rc 2 here.
run_pwsh "PS hs: the expandable spelling of the reduction disagreement (blocked)" \
  "$(printf '%s\n%s\n%s' "note \"a'b\" 'c' @\"" "\$(& \$g push --force)" "\"@")" 2
# THE COST of that shape, pinned rather than left to be re-found: the refusal is
# by SHAPE, so a git-free body carrying no `$(` at all blocks too.
run_pwsh "PS hs: the expandable disagreement over a plain body (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "note \"a'b\" 'c' @\"" "hello" "\"@")" 2

# RECORDED RESIDUALS, not endorsements. Both are rc 0 on this change and on its
# base, at default configuration with no allow token, and both are pinned so
# neither is re-found as new.
#
# A BLOCK COMMENT opened on an EARLIER line. The opener line is a bare `@"` with
# no `#` on it at all, so the per-line opener test takes it, and the `#>` and the
# live git line go as body. Carrying block-comment state across lines is a wider
# decision than this change.
run_pwsh "PS hs: RECORDED RESIDUAL: an interior-line block comment still opens a phantom here-string (allowed)" \
  "$(printf '%s\n%s\n%s\n%s\n%s' "<# note" "@\"" "#>" "git push --force" "\"@ fine\"")" 0
# The same residual with the opener on the wrapper's OWN second line, which is the
# shape the apostrophe cases above close. With no apostrophe the two reductions
# agree that `note @'` is a clean opener, so both trees confirm it and the payload
# goes as body. The quadrant rule moves nothing where the two reductions AGREE,
# and they agree here, so both trees drop the payload.
run_pwsh "PS hs: RECORDED RESIDUAL: a wrapped opener both reductions confirm (allowed)" \
  "$(printf '%s\n%s\n%s\n%s\n%s' "<#" "note @'" "#>" "& ('g'+'it') push --force" "'@'")" 0
# A COMMENT truncated by a LONE CR. PowerShell emits a NewLine token for a bare
# CR, so `git push --force` is live top-level code. Nothing in the guard treats a
# bare CR as a line break: hook::jq_fields strips it out of the command and
# ps::_split_lines_to splits on LF alone, so the live line is folded into the
# comment. Same CR handling as the lone-CR here-string 0.35.1 records; changing
# it is library-wide and out of this change's scope. The `#\n` twin below is the
# control proving the fixture discriminates.
run_pwsh "PS hs: RECORDED RESIDUAL: a lone CR truncating a # comment leaves the rest live (allowed)" \
  "$(printf '#\rgit push --force')" 0
run_pwsh "PS hs: control, the LF twin of that comment is refused" \
  "$(printf '#\ngit push --force')" 2

# RECORDED RESIDUAL, not an endorsement: `-MemberName` dispatch calls a METHOD on
# the filtered object rather than running a program named by the compared value,
# so the read-only allowlist admits it and these stay allowed. Pinned so a later
# narrowing that reaches method dispatch flips a test instead of passing silently.
run_pwsh "PS cmp: ForEach-Object -MemberName Kill stays where it is (allowed)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | ForEach-Object -MemberName Kill" 0
run_pwsh "PS cmp: ForEach-Object -MemberName with -ArgumentList stays where it is (allowed)" \
  "Get-Process | ? { \$_.Name -eq 'git' } | ForEach-Object -MemberName Start -ArgumentList push,--force" 0

malformed_rc=0
(cd "$REPO_SHA1" && bash "$HOOK" <<<'not json at all' >/dev/null 2>&1) || malformed_rc=$?
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
nul_payload() {
  jq -n --arg h "$1" --arg t "$2" \
    '{tool_name:"Bash",tool_input:{command:($h + ([0] | implode) + $t)}}'
}
run_nul() {
  local label="$1" head="$2" tail="$3" expected="$4"
  expect "$label" "$expected" --payload "$(nul_payload "$head" "$tail")" --chdir "$REPO_SHA1"
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
  guard_invoke --payload "$(nul_payload "$1" "$2")"
  printf '%s' "$GUARD_ERR"
  return "$GUARD_RC"
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

# --- #2965: an apostrophe in a DOUBLE-quoted string is not a span delimiter -----
# ps::blank_quoted_spans_to used to pair quotes with two independent `sed`
# expressions, neither aware of which style opened first. The single-quote
# expression matched from the apostrophe inside one double-quoted string to the
# apostrophe inside the next and DELETED everything between them:
#
#   in:  Write-Host "a'b"; & ('g'+'it') push --force; Write-Host "c'd"
#   out: Write-Host
#
# With the `(` gone, has_special_constructs saw no construct and the fail-closed
# sink was never ENTERED — so every downstream measuring probe was moot. Each
# command below blocks on its own; adding two ordinary apostrophe-bearing strings
# is what made it vanish. The controls are load-bearing: without them an
# all-blocked column is equally consistent with a guard that refuses every
# command containing an apostrophe.
# shellcheck disable=SC2016
run_pwsh "PS: computed git push --force (control, blocked)" \
  "& ('g'+'it') push --force" 2
# shellcheck disable=SC2016
run_pwsh "PS: same call straddled by apostrophe-bearing strings (blocked — #2965)" \
  "Write-Host \"a'b\"; & ('g'+'it') push --force; Write-Host \"c'd\"" 2
# shellcheck disable=SC2016
run_pwsh "PS: natural-prose spelling, variable target (blocked — #2965)" \
  "Write-Host \"Kyle's build\"; & (\$tool) push --force; Write-Host \"that's all\"" 2
# The REVERSED pairing — a double quote inside SINGLE-quoted strings — is the same
# defect with the roles swapped, and must stay closed by the same walk.
# shellcheck disable=SC2016
run_pwsh "PS: reversed straddle, quotes inside single-quoted strings (blocked — #2965)" \
  "Write-Host 'a\"b'; & ('g'+'it') push --force; Write-Host 'c\"d'" 2
# AMBIGUITY RESOLVES TOWARD NOT DELETING. An UNTERMINATED opener must not swallow
# the rest of the line, a BACKTICK-escaped quote must not extend the span to the
# next real one (honoring the escape here is what would reopen this bug in a new
# spelling), and PowerShell's DOUBLED-quote escape is deliberately over-blocked.
# shellcheck disable=SC2016
run_pwsh "PS: unterminated opener does not swallow the command (blocked — #2965)" \
  "Write-Host \"oops; & ('g'+'it') push --force" 2
# shellcheck disable=SC2016
run_pwsh "PS: backtick-escaped quote does not extend the span (blocked — #2965)" \
  "Write-Host \"a\`\"; & ('g'+'it') push --force; Write-Host \"b\"" 2
# shellcheck disable=SC2016
run_pwsh "PS: doubled-quote escape over-blocks rather than deletes (blocked — #2965)" \
  "Write-Host 'it''s'; & ('g'+'it') push --force" 2
# The escape cases have a SECOND failure mode: ending a span AT the backticked
# quote would leave the string's REAL closer behind as a stray opener, which
# then pairs with a quote far to the right and deletes the command anyway. Both
# escapes therefore delete NOTHING on their line. Pinned on the exact reviewed
# spelling.
# shellcheck disable=SC2016
run_pwsh "PS: escaped quote's real closer must not re-pair rightward (blocked — #2965)" \
  "\"a\`\"\"; & ('g'+'it') push --force; 'b\"c'" 2
# A lone EMPTY string is not a doubled quote — its closer is followed by
# something other than the same quote — so it must still blank normally rather
# than fall into the delete-nothing branch and start over-blocking.
# shellcheck disable=SC2016
run_pwsh "PS: empty string still blanks normally (allowed — #2965)" \
  "Write-Host \"\"; & \$py script.py" 0
# Over-block rails. Message text must stay inert, and the #2848 must-allow shapes
# must survive an apostrophe appearing beside them — more text is now VISIBLE to
# every probe, so this is exactly where a new over-block would surface.
run_pwsh "PS: apostrophe in a commit message stays inert (allowed — #2965)" \
  "git commit -m \"it's a fix\"" 0
run_pwsh "PS: two apostrophe-bearing strings, no command between (allowed — #2965)" \
  "Write-Host \"Kyle's build\"; Write-Host \"that's all\"" 0
# shellcheck disable=SC2016
run_pwsh "PS: #2848 bare-computed call target flanked by an apostrophe (allowed — #2965)" \
  "Write-Host \"Kyle's build\"; & \$py \$script (Join-Path \$dir \"\$id.jsonl\")" 0
# shellcheck disable=SC2016
run_pwsh "PS: #2848 apostrophe inside the grouped operand itself (allowed — #2965)" \
  "& \$py \$script (Join-Path \$dir \"that's.jsonl\")" 0

# --- #2906 containment: quoted Path+Value is a write, not a git signal ----------
# The placeholder lives only inside write_bypass's positional probe. These rows
# must stay allowed here so a contained write-lane fix cannot leak into the
# git fail-closed sink.
# shellcheck disable=SC2016
run_pwsh "PS: quoted Path+Value is not a git signal (allowed — #2906 containment)" \
  "& \$w 'f.txt' 'x'" 0
# shellcheck disable=SC2016
run_pwsh "PS: quoted Path+Value flanked by an apostrophe (allowed — #2906 containment)" \
  "Write-Host \"it's fine\"; & \$w 'f.txt' 'x'" 0

# --- Process creations on the guard's own paths (#3529) ----------------------
# run-guards.test.sh pins the dispatcher's PATH-visible execs through shims, and
# a shim cannot see a fork: `$(builtin-only function)`, `< <(printf …)` and a
# substitution whose body carries its own redirect each create a process that
# never execs (or, for the redirect case, a second process for one exec). The
# kernel is the instrument that counts them: strace follows the dispatcher's
# subshells (-f) and reports each clone/clone3/fork/vfork return, and execve
# separately, so an exec cannot pass for a removed fork or the reverse. The
# guard's own share is the difference against a no-op guard dispatched through
# the same run-guards.sh on the same payload, which subtracts the dispatcher's
# stdin, jq and isolation forks. HOOK_TELEMETRY_SINK is cleared: the envelope is
# opt-in and off by default, and it is the one path that still derives the
# subject through a substitution. A host without a working strace (Windows Git
# Bash, macOS) skips visibly; the Linux CI lane is where the pins hold.
#
# The benign pin is EXACT on purpose. The two creations that used to remain
# were `$(hook::buffer_stdin)` and the shared parser's `< <(printf …)`, both
# in lib/hook-utils.sh; those landed in #3740/#3838, so the guard's own share
# on a benign Bash call is now zero. A count that rises is a fork put back on
# every Bash call. The other pins are DELTAS against that benign share, so they
# read the cost of one path (a `!` alias reparse, its trailing arguments, the
# hash-width probe) rather than the library's total. Under -f strace may split
# a call into `<unfinished ...>` and `<... resumed>` halves, so both spellings
# of a completed call are counted.
strace_census() { # <payload> <guard> → CENSUS_RC CENSUS_CREATIONS CENSUS_EXECVE
  local log="$TEST_TMPDIR/strace.log"
  CENSUS_RC=0
  (cd "$REPO_SHA1" && env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR= \
    strace -f -e trace=clone,clone3,fork,vfork,execve -o "$log" \
    bash "$HOOK_DIR/run-guards.sh" "$2" <<<"$1" >/dev/null 2>&1) || CENSUS_RC=$?
  CENSUS_CREATIONS=$(grep -cE '((clone|clone3|fork|vfork)\(|<\.\.\. (clone|clone3|fork|vfork) resumed>).* = [0-9]+$' "$log")
  CENSUS_EXECVE=$(grep -cE '(execve\(|<\.\.\. execve resumed>).* = 0$' "$log")
}
# guard_share <command> → SHARE_RC SHARE_CREATIONS SHARE_EXECVE (guard minus no-op)
guard_share() {
  local payload noop_cre noop_exe
  payload="$(command_json_cwd "$1" "$REPO_SHA1")"
  strace_census "$payload" "$TEST_TMPDIR/noop-guard.sh"
  noop_cre=$CENSUS_CREATIONS
  noop_exe=$CENSUS_EXECVE
  strace_census "$payload" block-dangerous-git.sh
  SHARE_RC=$CENSUS_RC
  SHARE_CREATIONS=$((CENSUS_CREATIONS - noop_cre))
  SHARE_EXECVE=$((CENSUS_EXECVE - noop_exe))
}
if command -v strace >/dev/null 2>&1 && strace -o /dev/null -e trace=execve true 2>/dev/null; then
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMPDIR/noop-guard.sh"

  guard_share 'git status --short'
  benign_creations=$SHARE_CREATIONS
  assert_exit "strace: dispatched benign command exits 0" 0 "$SHARE_RC"
  assert_eq "strace: guard's own process creations on a benign Bash call" 0 "$SHARE_CREATIONS"
  assert_eq "strace: guard's own execve count on a benign Bash call" 0 "$SHARE_EXECVE"

  # The verdict path costs nothing the benign path did not: the eager telemetry
  # subject is gone from file scope, and emit_tel's own substitution stays
  # behind the sink gate.
  guard_share 'git push --force origin main'
  assert_exit "strace: dispatched force-push still blocks under the tracer" 2 "$SHARE_RC"
  assert_eq "strace: a blocked force-push creates no more processes than a benign call" \
    "$benign_creations" "$SHARE_CREATIONS"

  # A `!` alias reparse composes the relocated base without a fork
  # (hook::git_effective_dir_to assigns; no command substitution). The shared parser's
  # `< <(printf …)` re-entry is gone with #3838, so the reparse adds nothing
  # over the benign share.
  guard_share "git -c alias.y='!git status' y"
  alias_creations=$SHARE_CREATIONS
  assert_exit "strace: dispatched benign ! alias exits 0" 0 "$SHARE_RC"
  assert_eq "strace: a ! alias reparse adds no process creations over benign" \
    "$benign_creations" "$SHARE_CREATIONS"

  # Trailing arguments are shell-quoted with `printf -v`, so three of them add
  # nothing to the reparse's count.
  guard_share "git -c alias.y='!git push' y --force origin main"
  assert_exit "strace: force-push through a ! alias's trailing args still blocks under the tracer" 2 "$SHARE_RC"
  assert_eq "strace: trailing ! alias arguments add no process creations" \
    "$alias_creations" "$SHARE_CREATIONS"

  # The hash-width probe is the guard's one external command. Its `2>&1` must
  # stay inside the substitution (git's stderr is quoted by the block message),
  # so the body is `exec git …`: one creation and one execve, not two and one.
  guard_share "git push --force-with-lease=main:$SHA1_OID origin main"
  assert_exit "strace: lease pinned to a full SHA-1 object id still allowed under the tracer" 0 "$SHARE_RC"
  assert_eq "strace: the hash-width probe is one creation over benign" \
    $((benign_creations + 1)) "$SHARE_CREATIONS"
  assert_eq "strace: the hash-width probe is one execve" 1 "$SHARE_EXECVE"

  # Same site, per-process: standalone (so the guard's main bash is the parent
  # of every substitution it opens), the process that execs `git rev-parse
  # --show-object-format` must have a parent that itself execve'd. A parent that
  # never exec'd is the substitution's own subshell forking a second time,
  # which is the shape the `exec` removed.
  probe_log="$TEST_TMPDIR/strace-probe.log"
  (cd "$REPO_SHA1" && env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR= \
    strace -f -s 512 -e trace=clone,clone3,fork,vfork,execve -o "$probe_log" \
    bash "$HOOK" <<<"$(command_json_cwd "git push --force-with-lease=main:$SHA1_OID origin main" "$REPO_SHA1")" >/dev/null 2>&1)
  probe_direct=$(awk '
    { pid = $1 }
    (/clone\(|clone3\(|vfork\(|[^e]fork\(/ || /clone resumed|fork resumed/) && / = [0-9]+$/ {
      n = split($0, a, " = "); child = a[n]
      if (child ~ /^[0-9]+$/) parent[child] = pid
    }
    /execve\(/ && / = 0$/ { execed[pid] = 1; if ($0 ~ /"rev-parse", "--show-object-format"/) probe = pid }
    END {
      if (probe == "") { print "absent"; exit }
      q = (probe in parent) ? parent[probe] : "-"
      print (q in execed) ? "direct" : "extra-fork"
    }' "$probe_log")
  assert_eq "strace: the hash-width probe execs in the substitution's own subshell" direct "$probe_direct"
else
  echo "ok: process-creation pins skipped (no working strace on this host)"
fi

# --- The same verdicts under the dispatcher ----------------------------------
# The census above drives run-guards.sh but discards stdout and asserts a
# process count, never a verdict. hooks.json ships this guard under the
# dispatcher, where `.tool_input.command`, `.tool_name` and `.cwd` all arrive
# from the dispatcher's primed jq cache rather than the guard's own jq call —
# and this guard reads `.cwd` to pick the repository whose hash width judges a
# lease, so a cache that answered the wrong field would change the verdict.
expect_both "dispatched parity: git push --force blocks" 2 \
  --command "git push --force" --cwd "$REPO_SHA1" --chdir "$REPO_SHA1"
expect_both "dispatched parity: git push origin main allowed" 0 \
  --command "git push origin main" --cwd "$REPO_SHA1" --chdir "$REPO_SHA1"
expect_both "dispatched parity: lease pinned to a full SHA-1 object id allowed" 0 \
  --command "git push --force-with-lease=main:$SHA1_OID origin main" \
  --cwd "$REPO_SHA1" --chdir "$REPO_SHA1"
expect_both "dispatched parity: the same lease is a ref name in a SHA-256 repo" 2 \
  --command "git push --force-with-lease=main:$SHA1_OID origin main" \
  --cwd "$REPO_SHA256" --chdir "$REPO_SHA256"
expect_both "dispatched parity: git reset --hard blocks" 2 \
  --command "git reset --hard" --cwd "$REPO_SHA1" --chdir "$REPO_SHA1"
expect_both "dispatched parity: PowerShell git push --force blocks" 2 \
  --tool PowerShell --lib lib/powershell/ps-command.sh \
  --command "git push --force" --cwd "$REPO_SHA1" --chdir "$REPO_SHA1"

report
