#!/usr/bin/env bash
# worktree-create-gate.sh — WorktreeCreate hook: place every worktree Claude Code
# creates at the configured EXTERNAL root, never the in-repo `.claude/worktrees/`.
#
# The `/worktree create` skill already routes through scripts/worktree-create.sh,
# but three creation paths bypass the skill entirely — `claude --worktree`, a
# subagent with `isolation: "worktree"`, and a background session. Those land in
# the in-repo default, where a read matching a path-scoped rule's glob also loads
# the PARENT checkout's copy of that rule. This hook is the seam that covers them,
# and it is a thin stdin adapter over the same helper so there is one placement
# implementation rather than two.
#
# Contract (measured on 2.1.224, not inferred):
#   * stdin is one JSON object: session_id, transcript_path, cwd,
#     hook_event_name="WorktreeCreate", name — `name` being the requested
#     worktree name, `cwd` the session's repository.
#   * stdout's LAST NON-EMPTY LINE is taken as the worktree path. Extra lines are
#     tolerated: a hook printing a banner line before the path still succeeds and
#     the session lands in the printed directory. (The contrary claim — that any
#     output but the path fails the session — was tested and is false.) This hook
#     still prints the path alone; the tolerance is the safety margin, not the
#     interface.
#   * The hook REPLACES git's own worktree creation. Nothing registers a worktree
#     unless the hook does it, which is why this delegates to the helper rather
#     than merely computing a path.
#   * A user-scope hook fires. Verified with settings.json under a
#     CLAUDE_CONFIG_DIR, on a headless run, before login was even resolved.
#   * ${CLAUDE_PROJECT_DIR} is the project root the session started in — never the
#     worktree being created. The repository is taken from stdin's `cwd` for the
#     same reason: it is the value the event itself carries.
#
# Fail-closed by design. A hook failure fails the creation, and that is the
# correct direction here: falling through to Claude Code's default would place the
# worktree at exactly the nested path this exists to prevent. The unconfigured
# case is not a failure — it resolves to the plugin data directory, which is also
# outside every repository.
#
# Opt out with the `worktree_create_gate_enabled` plugin option.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hook-utils.sh
. "$HOOK_DIR/hook-utils.sh"

# Disabled means "let Claude Code use its own default", which is exit 0 with an
# empty stdout — a non-zero exit would fail the creation instead.
#
# The notice goes to stderr and nowhere else, deliberately. On this event stdout
# IS the path channel: the sanctioned `hook::emit_skip_notice` writes a JSON
# object to stdout, and here that object would be read as the worktree path. So
# this event has no visible-notice channel at all, and a stderr line on an exit-0
# path is discarded by the harness. The skip is therefore quiet by the event's
# construction rather than by choice — recorded here because a quiet skip is
# otherwise a defect under this repo's prerequisite-visibility doctrine.
# silent-skip-ok: WorktreeCreate reads stdout as the worktree path, so no
# visibility channel exists that would not corrupt the return value.
# The flag is read directly rather than through `hook::check_enabled`, which EXITS
# 0 itself instead of returning — anything a caller writes after it is dead code.
# Same variable, same default; the one extra line is what lets the notice reach
# stderr before the exit.
if [[ "${CLAUDE_PLUGIN_OPTION_WORKTREE_CREATE_GATE_ENABLED:-true}" != "true" ]]; then
  printf 'worktree-create-gate: disabled by worktree_create_gate_enabled=false; Claude Code will place this worktree at its own default, which may be inside the repository\n' >&2
  exit 0
fi

payload="$(hook::buffer_stdin)"

# jq is the primary reader; the fallback exists because failing the creation over
# an absent optional CLI would be a worse outcome than a bounded string extract of
# two flat, harness-generated string fields.
json_field() {
  local field="$1" value=""
  if command -v jq >/dev/null 2>&1; then
    value="$(hook::jq_field "$payload" ".$field")" || value=""
  fi
  if [[ -z "$value" ]]; then
    value="$(printf '%s' "$payload" |
      sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
      head -n 1 | tr -d '\r')"
    # The harness emits JSON-escaped Windows paths, so a fallback read has to undo
    # the one escape those paths actually carry.
    value="${value//\\\\/\\}"
  fi
  printf '%s' "$value"
}

name="$(json_field name)"
repo_dir="$(json_field cwd)"

if [[ -z "$name" ]]; then
  printf 'worktree-create-gate: the WorktreeCreate payload carried no .name; refusing rather than guessing a worktree name\n' >&2
  exit 1
fi
if [[ -z "$repo_dir" ]]; then
  repo_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# Root resolution mirrors the skill's, and deliberately reads the option from the
# environment rather than substituting `${user_config.worktree_root}` into a
# command: a value substituted into a shell field would be executed by the shell,
# which is why Claude Code rejects that form outright and exports
# CLAUDE_PLUGIN_OPTION_<KEY> instead.
root="${CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT:-}"
# An unexpanded placeholder is an unset value wearing a string's clothes.
# SC2016: the single-quoted ${user_config token is matched literally on purpose —
# the UNexpanded placeholder is exactly what is being detected, so expanding it
# here would defeat the check. Same rationale and same form as
# scripts/worktree-create.sh:230.
# shellcheck disable=SC2016
case "$root" in
*'${user_config'*) root="" ;;
*) ;;
esac

helper="$HOOK_DIR/../scripts/worktree-create.sh"
if [[ ! -f "$helper" ]]; then
  printf 'worktree-create-gate: helper not found at %s\n' "$helper" >&2
  exit 1
fi

args=(--name "$name" --repo-dir "$repo_dir")
if [[ -n "$root" ]]; then
  args+=(--root "$root")
else
  # No configured root: fall back to the plugin data directory, which is harness
  # state rather than a checkout, so it satisfies the outside-every-repository
  # invariant on its own. Passed through the helper's file channel because that is
  # the interface the helper documents for a value it must read verbatim.
  data_root="${CLAUDE_PLUGIN_DATA:-}"
  if [[ -z "$data_root" ]]; then
    printf 'worktree-create-gate: neither worktree_root nor CLAUDE_PLUGIN_DATA is set; refusing rather than letting the worktree land inside the repository\n' >&2
    exit 1
  fi
  root_file="$(mktemp "${TMPDIR:-/tmp}/worktree-create-gate.XXXXXX")" || {
    printf 'worktree-create-gate: cannot create a temp file for the data-root handoff\n' >&2
    exit 1
  }
  trap 'rm -f "$root_file"' EXIT
  printf '%s' "$data_root" >"$root_file"
  args+=(--data-root-file "$root_file")
fi

if ! path="$(bash "$helper" "${args[@]}")"; then
  status=$?
  printf 'worktree-create-gate: %s exited %s; worktree not created\n' "$helper" "$status" >&2
  exit 1
fi

if [[ -z "$path" ]]; then
  printf 'worktree-create-gate: helper succeeded but printed no path\n' >&2
  exit 1
fi

printf '%s\n' "$path"
