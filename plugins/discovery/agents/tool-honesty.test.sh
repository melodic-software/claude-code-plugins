#!/usr/bin/env bash
# Contract test for the agent definitions in this directory.
#
# The defect this locks: `agents/researcher.md` carried a "Tool honesty"
# paragraph copied from `agents/explorer.md`, where it is true. The explorer
# declares a `tools:` allowlist that omits `Edit`, so "Edit is absent from your
# tool list" is a property of that file. The researcher declares no allowlist at
# all — it inherits every tool available to a subagent, `Edit` included — so the
# same sentence sitting in that file was simply false, and it was the calibration
# input for a write boundary the file itself says is held by instruction only.
#
# Least-privilege UNDERSTATEMENT is the dangerous polarity: an agent told it
# cannot do something it can do will not guard against doing it. The class is
# mechanically detectable, so it is checked here rather than left to review.
#
# Scoped to plugins/discovery/agents/*.md on purpose. A sweep over every
# plugin's agents would fail this plugin's test on another plugin's drift, which
# reports the defect in the wrong place and blocks the wrong change.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# frontmatter <file> — the YAML block between the first two `---` lines.
frontmatter() {
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside' "$1"
}

# body <file> — everything after the frontmatter.
body() {
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {inside=0; started=1; next} started' "$1"
}

# fm_value <file> <key> — the raw value of a top-level frontmatter key, or "".
fm_value() {
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | tr -d '"'
}

# A literal backtick, built rather than quoted. The prose these checks match
# names its tools in markdown code spans, and a backtick inside a shell literal
# reads as command substitution to every linter that looks at this file.
BT="$(printf '\140')"

# claims_about <file> <predicate> — every tool name the body asserts <predicate>
# about, one per line, deduplicated. Matching the sentence SHAPE rather than a
# fixed tool name means a future paragraph making the same claim about a
# different tool is covered without editing this test.
claims_about() {
  body "$1" |
    grep -oE "${BT}[A-Za-z]+${BT} $2" |
    grep -oE "${BT}[A-Za-z]+${BT}" |
    tr -d "$BT" |
    sort -u
}

shopt -s nullglob
agents=(*.md)
shopt -u nullglob

if [[ ${#agents[@]} -eq 0 ]]; then
  echo "error: no agent definitions found beside this test" >&2
  exit 2
fi

for agent in "${agents[@]}"; do
  tools="$(fm_value "$agent" tools)"
  denied="$(fm_value "$agent" disallowedTools)"

  # ---------------------------------------------------------------------------
  # 1. A file that says a tool is absent from its tool list must actually
  #    declare a tool list, and that list must actually omit the tool.
  #
  #    The claim is matched on the sentence shape the two files share rather
  #    than on a fixed tool name, so a future paragraph making the same claim
  #    about a different tool is covered without editing this test.
  # ---------------------------------------------------------------------------
  while IFS= read -r claimed; do
    [[ -n "$claimed" ]] || continue

    if [[ -z "$tools" ]]; then
      fail "$agent: prose says \`$claimed\` is absent from its tool list, but no \`tools:\` key is declared — with no allowlist the pool is inherited and \`$claimed\` is held"
      continue
    fi

    if [[ ",${tools// /}," == *",$claimed,"* ]]; then
      fail "$agent: prose says \`$claimed\` is absent from its tool list, but \`tools:\` lists it"
      continue
    fi

    pass "$agent: the claim that \`$claimed\` is absent is backed by the \`tools:\` allowlist"
  done < <(claims_about "$agent" 'is absent from your tool list')

  # ---------------------------------------------------------------------------
  # 2. A file that claims a tool is LISTED must declare a list containing it.
  #    Same defect, opposite polarity: the researcher asserted `Agent` was
  #    listed in frontmatter that listed nothing.
  # ---------------------------------------------------------------------------
  while IFS= read -r claimed; do
    [[ -n "$claimed" ]] || continue

    if [[ -z "$tools" ]]; then
      fail "$agent: prose says \`$claimed\` is listed, but no \`tools:\` key is declared — it is inherited, not listed"
      continue
    fi

    if [[ ",${tools// /}," != *",$claimed,"* ]]; then
      fail "$agent: prose says \`$claimed\` is listed, but \`tools:\` does not list it"
      continue
    fi

    pass "$agent: the claim that \`$claimed\` is listed is backed by the \`tools:\` allowlist"
  done < <(claims_about "$agent" 'is listed')

  # ---------------------------------------------------------------------------
  # 3. Every agent declares its posture one way or the other. An agent with
  #    neither key inherits everything silently, which is how the original
  #    defect became invisible: nothing in the file said what it held, so the
  #    prose was the only inventory and nobody rechecked it.
  # ---------------------------------------------------------------------------
  if [[ -z "$tools" && -z "$denied" ]]; then
    fail "$agent: declares neither \`tools:\` nor \`disallowedTools:\` — the inherited pool is then undeclared, and the prose becomes the only inventory"
  else
    pass "$agent: declares its tool posture in frontmatter"
  fi

  # ---------------------------------------------------------------------------
  # 4. Both agents' artifacts are graded off disk by the parent, in the parent's
  #    checkout. `isolation: worktree` writes them into an isolated copy the
  #    gate never looks at, so the run reads as having produced nothing. The
  #    decision to stay un-isolated is deliberate; this keeps it deliberate.
  # ---------------------------------------------------------------------------
  if [[ -n "$(fm_value "$agent" isolation)" ]]; then
    fail "$agent: sets \`isolation:\` — an isolated checkout puts the artifact set where the parent's acceptance gate cannot see it"
  else
    pass "$agent: does not set \`isolation:\`, so its writes land where the gate grades"
  fi

  # ---------------------------------------------------------------------------
  # 5. The by-value recovery rung only exists if the payload can express it.
  # ---------------------------------------------------------------------------
  if body "$agent" | grep -q '^persistence: '; then
    pass "$agent: the return payload carries a \`persistence:\` axis"
  else
    fail "$agent: the return payload has no \`persistence:\` field — a completed run whose write was refused cannot be told apart from one that never ran"
  fi

  # ---------------------------------------------------------------------------
  # 6. The echo-back field. Every other check in the acceptance gate keys on
  #    absence; this is the only one that can fire on an input that is present
  #    and wrong.
  # ---------------------------------------------------------------------------
  if body "$agent" | grep -qE '^(scope|topic)_as_received: '; then
    pass "$agent: the return payload echoes back the scope/topic as received"
  else
    fail "$agent: the return payload has no \`scope_as_received:\`/\`topic_as_received:\` field — a corrupted input passes every gate"
  fi
done

if [[ "$fails" -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "$fails" >&2
  exit 1
fi
printf '\nall tests passed\n'
