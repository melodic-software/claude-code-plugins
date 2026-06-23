#!/usr/bin/env bash
# Minimal hook utility library for the markdown-formatter plugin.
# Sourced (not executed). Trimmed subset of a larger shared library — only the
# functions this plugin's hook needs: kill switch, file_path parsing + path
# normalization, repo-root resolution, and the additionalContext accumulator.

# Guard against double-sourcing.
[[ -n "${_MDFMT_HOOK_UTILS_LOADED:-}" ]] && return 0
readonly _MDFMT_HOOK_UTILS_LOADED=1

# Per-hook kill switch via HOOK_<NAME>_ENABLED env var. Exits 0 (allow) if
# disabled. Place after source, before stdin parsing.
#   hook::check_enabled "MARKDOWN_FORMAT"  # checks HOOK_MARKDOWN_FORMAT_ENABLED
hook::check_enabled() {
  local var_name="HOOK_${1}_ENABLED"
  if [[ "${!var_name:-true}" != "true" ]]; then
    exit 0
  fi
}

# Normalize a path: backslashes → forward slashes, then POSIX/lowercase drive
# letter → uppercase Windows drive letter (idempotent). On macOS/Linux the
# regex does not match (multi-char first segments) — no-op.
hook::normalize_path() {
  local p="${1//\\//}"
  if [[ "$p" =~ ^/([a-zA-Z])/ || "$p" =~ ^([a-zA-Z]):/ ]]; then
    printf '%s' "${BASH_REMATCH[1]^}:${p:2}"
  else
    printf '%s' "$p"
  fi
}

# Parse file_path from PostToolUse JSON on stdin; validate existence and (when
# CLAUDE_PROJECT_DIR is set) project membership. Outputs the path on success.
# Returns 1 to skip.
#   FILE=$(hook::read_file_path) || exit 0
hook::read_file_path() {
  local file
  file=$(jq -r '(.tool_input.file_path // empty) | gsub("\r";"")' 2>/dev/null)
  [[ -n "$file" ]] || return 1
  [[ -f "$file" ]] || return 1
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    local norm_file norm_project
    norm_file=$(hook::normalize_path "$file")
    norm_project=$(hook::normalize_path "${CLAUDE_PROJECT_DIR}")
    if [[ "$norm_file" != "$norm_project"* ]]; then
      return 1
    fi
  fi
  printf '%s' "$file"
}

# Resolve the repository root (working-tree top) for a path inside the tree.
# markdownlint config auto-discovery is CWD-anchored, so the hook cd's here
# before linting. File-anchored (`git -C "$hint" rev-parse --show-toplevel`)
# so it is correct for clones, linked worktrees, and bare-hub clones; falls
# back to the hint (with a trailing /.claude stripped) when git cannot resolve.
#   ROOT=$(hook::repo_root "$some_path")
hook::repo_root() {
  local hint="${1:-.}"
  local root
  root=$(git -C "$hint" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
  if [[ -z "$root" ]]; then
    root="$hint"
    root="${root%/.claude}"
    root="${root%\\.claude}"
  fi
  printf '%s' "$root"
}

# Per-hook stdout context accumulator. ctx_reset at entry, ctx_append per line,
# ctx_flush once at exit with the hook event name.
_HOOK_CTX_BUFFER=""

hook::ctx_reset() {
  _HOOK_CTX_BUFFER=""
}

hook::ctx_append() {
  _HOOK_CTX_BUFFER+="$1"$'\n'
}

# Emit the accumulated context as hookSpecificOutput JSON, then clear the buffer.
hook::ctx_flush() {
  local event_name="$1"
  local trimmed="${_HOOK_CTX_BUFFER%"${_HOOK_CTX_BUFFER##*[![:space:]]}"}"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  hook::emit_additional_context "$event_name" "$trimmed"
  hook::ctx_reset
}

# Print cross-host hook JSON to stdout (exit 0). No-op when context is empty.
# Shape: { hookSpecificOutput: { hookEventName[, additionalContext] } }.
hook::emit_additional_context() {
  local event_name="$1"
  local context="$2"
  [[ -n "$context" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -n \
    --arg event "$event_name" \
    --arg ctx "$context" \
    '{hookSpecificOutput: (
      {hookEventName: $event}
      + (if $ctx != "" then {additionalContext: $ctx} else {} end)
    )}'
}
