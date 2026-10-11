#!/usr/bin/env bash
# confirm-gates.sh <sha>: list every confirm gate in the tree of one commit.
#
# Read-only. Reads the tree of <sha> through `git grep` and `git show`, never the
# working tree, so the count cannot drift while the audit table is built. Prints
# one row per hit: <source> TAB <file>:<line> TAB <text>, where source is one of
# skill, agent, convention, hook, settings. The text is data and is never
# evaluated.
#
# Sources (issue #7005, slice 93):
#   skill, agent, convention: one fixed prose pattern over skill markdown, agent
#     definitions, AGENTS.md and docs/conventions.
#   hook: non-test files under plugins/*/hooks/ whose code (not a comment line)
#     emits a PreToolUse permissionDecision of ask or deny. Exit-2 blocking
#     guards emit no permission decision and are outside this definition.
#   settings: .claude/settings.json permissions.ask entries.
set -euo pipefail

sha="${1:?usage: confirm-gates.sh <sha>}"
git cat-file -e "${sha}^{commit}"

pattern="AskUserQuestion|explicit (yes|go-ahead|approval|confirmation)|(ask|confirm)( with)?( the user)? before|wait(s)? for (the user|approval|a yes)|only on the user's (yes|go-ahead)"

# Prose gates. `git grep <sha>` prefixes each hit with "<sha>:".
# git grep exits 1 on no match; only a status above 1 is an error.
{ git grep -n -E "$pattern" "$sha" -- \
  ':(glob)plugins/*/skills/**/*.md' \
  ':(glob)plugins/*/agents/*.md' \
  'AGENTS.md' \
  ':(glob)docs/conventions/**/*.md' || (($? == 1)); } |
  while IFS= read -r hit; do
    rest="${hit#"$sha":}"
    file="${rest%%:*}"
    rest="${rest#*:}"
    line="${rest%%:*}"
    text="${rest#*:}"
    case "$file" in
      plugins/*/skills/*) source=skill ;;
      plugins/*/agents/*) source=agent ;;
      *) source=convention ;;
    esac
    printf '%s\t%s:%s\t%s\n' "$source" "$file" "$line" "$text"
  done

# Hook gates: code lines emitting permissionDecision ask or deny.
hook_re="permissionDecision[\"']?[[:space:]]*:[[:space:]]*[\"'](ask|deny)[\"']"
{ git grep -n -E "$hook_re" "$sha" -- \
  ':(glob)plugins/*/hooks/**' \
  ':(exclude,glob)plugins/*/hooks/**/*.test.*' \
  ':(exclude,glob)plugins/*/hooks/**/tests/**' || (($? == 1)); } |
  while IFS= read -r hit; do
    rest="${hit#"$sha":}"
    file="${rest%%:*}"
    rest="${rest#*:}"
    line="${rest%%:*}"
    text="${rest#*:}"
    case "$text" in
      [[:space:]]*'#'* | '#'* | [[:space:]]*'//'* | '//'* | [[:space:]]*'*'*) continue ;;
      *) ;;
    esac
    printf 'hook\t%s:%s\t%s\n' "$file" "$line" "$text"
  done

# Settings gates: permissions.ask entries, located by line in the pinned file.
settings="$(git show "$sha:.claude/settings.json")"
jq -r '.permissions.ask // [] | .[]' <<<"$settings" |
  while IFS= read -r rule; do
    line="$(grep -nF -- "\"$rule\"" <<<"$settings" | head -n 1 | cut -d: -f1)"
    printf 'settings\t.claude/settings.json:%s\t%s\n' "$line" "$rule"
  done
