# shellcheck shell=bash
# Config-scope resolution ladders for the audit scripts, library only.
#
# No top-level execution, no env-driven side effects, no exit calls. Each ladder
# writes its answer into the caller's variable (the repo's `_to` convention)
# and takes the caller's own override as its next argument, so every script
# keeps its own test-seam variable name while the ORDER of the fallbacks is
# shared. An override and an environment value land verbatim, exactly as the
# inline ladders assigned them; only the git toplevel passes through a command
# substitution, as it always did. Callers own presentation, normalization
# (backslash folding, trailing-slash stripping) and exit-code mapping.
#
# WHY THIS EXISTS: five audit scripts resolved the same three ladders by hand.
# A hand-written copy drifts the moment one of them learns a new fallback, and
# a scope resolved two ways inside one audit reports the same machine twice.

# scopes::project_root_to <var> [override] - the consumer project root: a
# non-empty <override> verbatim, then the cwd's git toplevel, then Claude
# Code's exported project dir, then the cwd. Never the plugin's own install
# directory.
#
# Git for Windows reports the toplevel with a trailing CR; it is stripped in the
# shell rather than through `tr` so the ladder costs no extra process.
scopes::project_root_to() {
  local -n _scopes_out="$1"
  local override="${2:-}" root
  if [[ -n "$override" ]]; then
    _scopes_out="$override"
    return 0
  fi
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  root="${root//$'\r'/}"
  _scopes_out="${root:-${CLAUDE_PROJECT_DIR:-$PWD}}"
}

# scopes::user_dir_to <var> [override] - the user config dir: a non-empty
# <override>, then CLAUDE_CONFIG_DIR, then $HOME/.claude. Leaves <var> empty
# when HOME is unset too, which callers read as "this machine has no user
# scope to read".
scopes::user_dir_to() {
  local -n _scopes_out="$1"
  local override="${2:-}"
  if [[ -n "$override" ]]; then
    _scopes_out="$override"
  elif [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    _scopes_out="$CLAUDE_CONFIG_DIR"
  elif [[ -n "${HOME:-}" ]]; then
    _scopes_out="$HOME/.claude"
  else
    _scopes_out=""
  fi
}

# scopes::installed_registry_to <var> [override] [user-dir] - the
# installed-plugin registry: a non-empty <override>, else the registry under a
# non-empty <user-dir>. Leaves <var> empty when neither is known, which callers
# read as "no registry to consult".
scopes::installed_registry_to() {
  local -n _scopes_out="$1"
  local override="${2:-}" user_dir="${3:-}"
  if [[ -n "$override" ]]; then
    _scopes_out="$override"
  elif [[ -n "$user_dir" ]]; then
    _scopes_out="$user_dir/plugins/installed_plugins.json"
  else
    _scopes_out=""
  fi
}
