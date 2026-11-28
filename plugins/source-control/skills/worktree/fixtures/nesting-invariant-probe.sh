#!/usr/bin/env bash

set -uo pipefail

WORKDIR="${1:-$(mktemp -d "${TMPDIR:-/tmp}/nestprobe.XXXXXX")}"
mkdir -p "$WORKDIR"
TRACE_DIR="$WORKDIR/traces"
mkdir -p "$TRACE_DIR"

command -v claude >/dev/null 2>&1 || {
  printf 'claude CLI not on PATH — cannot probe\n' >&2
  exit 1
}

CLAUDE_VERSION="$(claude --version 2>&1)"
printf 'workdir: %s\n' "$WORKDIR"
printf 'claude version: %s\n\n' "$CLAUDE_VERSION"

printf 'Pinned discriminators:\n'
printf '  creation:     plain git-worktree-add (not claude --worktree / EnterWorktree)\n'
printf '  launch:       cd <worktree> && claude -p … --settings <file> (bare cd into git-worktree-add dir)\n'
printf '  paths glob:   src/** (anchored at each rule file'\''s own repo root)\n'
printf '  parent rule:  COMMITTED in the parent checkout\n'
printf '  hook form:    InstructionsLoaded exec (args-array) via --settings\n'
printf '  placements:   dot-nested | plain-nested | external | unrelated-nested\n\n'

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

mksettings() {
  printf '{"hooks":{"InstructionsLoaded":[{"hooks":[{"type":"command","command":"bash","args":["%s"],"timeout":30}]}]}}\n' \
    "$HOOK" >"$1"
}
SETTINGS="$WORKDIR/trace-settings.json"
mksettings "$SETTINGS"

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
  local claude_err="$TRACE_DIR/$label.claude.err"
  ( cd "$wt" && claude -p "Read $readpath and reply with exactly: OK" \
      --settings "$SETTINGS" >"$TRACE_DIR/$label.claude.out" 2>"$claude_err" )
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
    # claude may put the failure on stdout or stderr depending on the path
    # (auth refusal was observed on stdout on 2.1.232).
    if [[ -s "$TRACE_DIR/$label.claude.out" || -s "$claude_err" ]]; then
      printf 'claude output (first lines):\n'
      { head -n 5 "$TRACE_DIR/$label.claude.out" 2>/dev/null; head -n 5 "$claude_err" 2>/dev/null; } \
        | sed '/^$/d' | head -n 5 | sed 's/^/  /'
    fi
  fi
  cp -f "$TRACE_DIR/trace.jsonl" "$TRACE_DIR/$label.jsonl" 2>/dev/null || true
  printf '\n'
}

GLOB="src/**"
printf 'paths: glob under test: %s (anchored at each rule file own repo root)\n\n' "$GLOB"

P1="$(mkparent "$WORKDIR/parentA" "$GLOB")"
arm dot-nested "$P1" "$P1/.claude/worktrees/wt" "src/target.md"

P2="$(mkparent "$WORKDIR/parentB" "$GLOB")"
arm plain-nested "$P2" "$P2/plainsub/wt" "src/target.md"

P3="$(mkparent "$WORKDIR/parentC" "$GLOB")"
arm external "$P3" "$WORKDIR/external-root/wt" "src/target.md"

P4="$(mkparent "$WORKDIR/parentD" "$GLOB")"
UNREL="$(mkparent "$WORKDIR/unrelated" "$GLOB")"
arm unrelated-nested "$P4" "$UNREL/nested/wt" "src/target.md"

printf 'traces: %s\n' "$TRACE_DIR"
printf 'Record the outcome — including a null — in fixtures/README.md, and refresh\n'
printf 'the as-of stamp in skills/worktree/reference/nesting-invariant.md with the verdict.\n'
