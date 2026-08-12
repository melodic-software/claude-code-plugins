#!/usr/bin/env bash
# nesting-invariant-probe.sh — adjudicate the nesting invariant's disputed arm.
#
# The claim: from a session inside a worktree nested in a checkout, a read
# matching a path-scoped rule's glob ALSO loads the enclosing checkout's copy of
# that rule. Measured once on 2.1.224 and not reproduced on 2.1.227 — and
# NEITHER run recorded its fixture, which is why the dispute is unadjudicable
# rather than settled. Every one of the following changes the outcome, and this
# script pins all of them:
#
#   * how the worktree was CREATED (`claude --worktree` / `EnterWorktree` /
#     plain `git worktree add`) — the harness's worktree-aware behavior attaches
#     to a session it RECOGNIZES as a worktree session, and a bare `cd` into a
#     `git worktree add` directory is not obviously one;
#   * how the session was LAUNCHED into it;
#   * the exact `paths:` glob AND the root it anchors against;
#   * whether the parent's rule file was COMMITTED (an untracked rule file in a
#     worktree's parent is not the same fixture as a tracked one);
#   * placement: dot-prefixed `.claude/worktrees/` vs a plain subdirectory vs an
#     UNRELATED repository — the three control arms are different claims.
#
# Instrument: an `InstructionsLoaded` hook, which NAMES the files loaded rather
# than inferring them from token deltas. Registered in exec (`args`-array) form
# per <https://code.claude.com/docs/en/hooks>: "Set `args` whenever the hook
# references a path placeholder, since each element is passed as one argument
# with no quoting." Both command forms are documented and neither is carved out
# for this event; if you probe the shell form here, RECORD the result, because
# whether it fires for `InstructionsLoaded` via `--settings` is unprobed.
#
# Passed via `claude -p --settings <file>` because a project-scope hook in an
# unapproved `settings.json` does not run headlessly.
#
# ─────────────────────────────────────────────────────────────────────────────
# STATUS: WRITTEN, NOT YET RUN. Nothing in fixtures/README.md's nesting section
# is claimed on this script's authority. It is the recheck PROCEDURE; running it
# is what converts the disputed arm into a settled one. Record the outcome in
# fixtures/README.md — including a null result, which is a finding here.
# ─────────────────────────────────────────────────────────────────────────────
#
# Costs one `claude -p` turn per arm. Network and an authenticated CLI required.
#
# Usage: bash nesting-invariant-probe.sh [workdir]

set -uo pipefail

WORKDIR="${1:-$(mktemp -d "${TMPDIR:-/tmp}/nestprobe.XXXXXX")}"
mkdir -p "$WORKDIR"
TRACE_DIR="$WORKDIR/traces"
mkdir -p "$TRACE_DIR"

command -v claude >/dev/null 2>&1 || {
  printf 'claude CLI not on PATH — cannot probe\n' >&2
  exit 1
}

printf 'workdir: %s\n' "$WORKDIR"
printf 'claude version: %s\n\n' "$(claude --version 2>&1)"

# The instrument. Appends every InstructionsLoaded payload verbatim, so the
# analysis reads what the harness said rather than what the probe inferred.
HOOK="$WORKDIR/instructions-loaded-trace.sh"
# SC2016: the single quotes are the point — these lines are the GENERATED hook's
# source, so `$payload` must reach that script unexpanded and be evaluated when
# the hook runs, not when this probe writes it. Only $TRACE_DIR is substituted,
# through printf's own %s.
# shellcheck disable=SC2016
{
  printf '#!/usr/bin/env bash\n'
  printf 'payload="$(cat)"\n'
  printf 'printf "%%s\\n" "$payload" >>"%s/trace.jsonl"\n' "$TRACE_DIR"
  printf 'exit 0\n'
} >"$HOOK"
chmod +x "$HOOK"

# Exec form: `command` is the interpreter, `args` the argument vector.
mksettings() {
  printf '{"hooks":{"InstructionsLoaded":[{"hooks":[{"type":"command","command":"bash","args":["%s"],"timeout":30}]}]}}\n' \
    "$HOOK" >"$1"
}
SETTINGS="$WORKDIR/trace-settings.json"
mksettings "$SETTINGS"

# A parent checkout carrying a path-scoped rule, COMMITTED — recorded because an
# untracked rule file is a different fixture and was never disambiguated.
mkparent() {
  local repo="$1" glob="$2"
  rm -rf "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email probe@probe.test
  git -C "$repo" config user.name probe
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/.claude/rules" "$repo/src"
  {
    printf -- '---\n'
    printf 'paths: ["%s"]\n' "$glob"
    printf -- '---\n\n'
    printf 'PARENT-RULE-MARKER: this rule belongs to the PARENT checkout.\n'
  } >"$repo/.claude/rules/scoped.md"
  printf 'parent target\n' >"$repo/src/target.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "parent checkout with a committed path-scoped rule"
  printf '%s' "$repo"
}

# One arm = one placement. `git worktree add` is used deliberately for the
# nested arms because the in-repo path is what is under test; the launch mode is
# recorded separately since it is the discriminator the original runs omitted.
arm() {
  local label="$1" repo="$2" wt="$3" readpath="$4"
  printf '=== %s ===\n' "$label"
  printf 'worktree:  %s\n' "$wt"
  printf 'read path: %s\n' "$readpath"
  rm -f "$TRACE_DIR/trace.jsonl"
  git -C "$repo" worktree add -q -b "wt-$label" "$wt" 2>/dev/null || {
    printf 'could not create the worktree — arm skipped\n\n'
    return
  }
  mkdir -p "$(dirname "$wt/$readpath")"
  printf 'worktree target\n' >"$wt/$readpath"
  ( cd "$wt" && claude -p "Read $readpath and reply with exactly: OK" \
      --settings "$SETTINGS" >/dev/null 2>&1 )
  if [[ -s "$TRACE_DIR/trace.jsonl" ]]; then
    printf 'rule files named in the trace:\n'
    grep -oE '"[^"]*scoped\.md"' "$TRACE_DIR/trace.jsonl" | sort -u | sed 's/^/  /'
    printf 'PARENT rule loaded? '
    if grep -qF "$repo/.claude/rules/scoped.md" "$TRACE_DIR/trace.jsonl"; then
      printf 'YES — the leak reproduces on this arm\n'
    else
      printf 'no\n'
    fi
  else
    printf 'NO TRACE EVENTS AT ALL — the hook did not fire. This is a fixture\n'
    printf 'failure, NOT evidence of absence. Fix the hook before reading any\n'
    printf 'arm as a null result; mistaking one for the other is how the\n'
    printf 'original dispute arose.\n'
  fi
  cp -f "$TRACE_DIR/trace.jsonl" "$TRACE_DIR/$label.jsonl" 2>/dev/null || true
  printf '\n'
}

GLOB="src/**"
printf 'paths: glob under test: %s (anchored at each rule file own repo root)\n\n' "$GLOB"

# Arm A — nested at the harness default, dot-prefixed.
P1="$(mkparent "$WORKDIR/parentA" "$GLOB")"
arm dot-nested "$P1" "$P1/.claude/worktrees/wt" "src/target.md"

# Arm B — nested at a PLAIN subdirectory. Isolates dot-prefixing from nesting.
P2="$(mkparent "$WORKDIR/parentB" "$GLOB")"
arm plain-nested "$P2" "$P2/plainsub/wt" "src/target.md"

# Arm C — the control: placed OUTSIDE every repository. Must show zero.
P3="$(mkparent "$WORKDIR/parentC" "$GLOB")"
arm external "$P3" "$WORKDIR/external-root/wt" "src/target.md"

# Arm D — nested inside an UNRELATED repository. Claimed WORSE (all three
# surfaces, not just scoped rules) and untested by anyone. Do not read a null
# here as refuting arm A: they are different claims.
P4="$(mkparent "$WORKDIR/parentD" "$GLOB")"
UNREL="$(mkparent "$WORKDIR/unrelated" "$GLOB")"
arm unrelated-nested "$P4" "$UNREL/nested/wt" "src/target.md"

printf 'traces: %s\n' "$TRACE_DIR"
printf 'Record the outcome — including a null — in fixtures/README.md, and refresh\n'
printf 'the as-of stamp in skills/worktree/SKILL.md with the verdict.\n'
