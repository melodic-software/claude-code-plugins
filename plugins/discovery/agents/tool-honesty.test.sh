#!/usr/bin/env bash
# test-scope: plugins/discovery/agents/*.md
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# shellcheck source=../lib/test-helpers.sh
source ../lib/test-helpers.sh

frontmatter() {
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside' "$1"
}

body() {
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {inside=0; started=1; next} started' "$1"
}

fm_value() {
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | tr -d '"'
}

BT="$(printf '\140')"

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
  agent_body="$(body "$agent")"
  tools="$(fm_value "$agent" tools)"
  denied="$(fm_value "$agent" disallowedTools)"

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

  if [[ -z "$tools" && -z "$denied" ]]; then
    fail "$agent: declares neither \`tools:\` nor \`disallowedTools:\` — the inherited pool is then undeclared, and the prose becomes the only inventory"
  else
    pass "$agent: declares its tool posture in frontmatter"
  fi

  if [[ -n "$(fm_value "$agent" isolation)" ]]; then
    fail "$agent: sets \`isolation:\` — an isolated checkout puts the artifact set where the parent's acceptance gate cannot see it"
  else
    pass "$agent: does not set \`isolation:\`, so its writes land where the gate grades"
  fi

  if [[ -n "$tools" && ",${tools// /}," != *",Write,"* ]]; then
    pass "$agent: read-only allowlist, so no \`persistence:\` axis is owed"
  elif grep -q '^persistence: ' <<<"$agent_body"; then
    pass "$agent: the return payload carries a \`persistence:\` axis"
  else
    fail "$agent: the return payload has no \`persistence:\` field — a completed run whose write was refused cannot be told apart from one that never ran"
  fi

  if [[ "$agent" == sweep-worker.md || "$agent" == docs-fetcher.md ]]; then
    pass "$agent: returns a workflow-schema structure, so no echo-back field is owed"
  elif grep -qE '^(scope|topic|target)_as_received: ' <<<"$agent_body"; then
    pass "$agent: the return payload echoes back the scope/topic/target as received"
  else
    fail "$agent: the return payload has no \`scope_as_received:\`/\`topic_as_received:\`/\`target_as_received:\` field — a corrupted input passes every gate"
  fi
done

if [[ "$fails" -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "$fails" >&2
  exit 1
fi
printf '\nall tests passed\n'
