# shellcheck shell=bash
# Resolves linkage_gate_uses_pattern: https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/source-control/reference/config-resolution.md#yaml-keys-docsconventionssource-controlyaml

[[ -n "${_PR_LINKAGE_SCOPE_LOADED:-}" ]] && return 0
_PR_LINKAGE_SCOPE_LOADED=1

_PLS_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_PLS_DIR" == "${BASH_SOURCE[0]}" ]] && _PLS_DIR=.
_PLS_YAML_REL="docs/conventions/source-control.yaml"
_PLS_KEY="linkage_gate_uses_pattern"

linkage::gate_file_to() {
  local __pls_dest="$1" __pls_root="$2" __pls_hook="$3"
  local __pls_re="${CLAUDE_PLUGIN_OPTION_LINKAGE_GATE_USES_PATTERN:-}"
  local __pls_file="$__pls_root/$_PLS_YAML_REL" __pls_text="" __pls_recs __pls_rc __pls_cand __pls_wf
  printf -v "$__pls_dest" %s ""
  if [[ -n "$__pls_root" && -f "$__pls_file" ]]; then
    IFS= read -r -d '' __pls_text <"$__pls_file"
    if [[ "$__pls_text" == *"$_PLS_KEY"* ]]; then
      { __pls_recs=$(LC_ALL=C awk -v STRICT=1 -f "$_PLS_DIR/../lib/yaml-subset.awk" "$__pls_file"); } 2>/dev/null || {
        printf '%s: %s does not parse; %s is unresolved, so the gate is off.\n' "$__pls_hook" "$_PLS_YAML_REL" "$_PLS_KEY" >&2
        return 0
      }
      __pls_recs=$'\n'"$__pls_recs"
      if [[ "$__pls_recs" == *$'\n'"$_PLS_KEY"$'\t'* ]]; then
        __pls_re="${__pls_recs#*$'\n'"$_PLS_KEY"$'\t'}"
        __pls_re="${__pls_re%%$'\n'*}"
      fi
    fi
  fi
  [[ -n "$__pls_re" ]] || return 0
  [[ "" =~ $__pls_re ]]
  __pls_rc=$?
  if ((__pls_rc == 2)); then
    printf '%s: %s is not a valid POSIX ERE; the gate is off.\n' "$__pls_hook" "$_PLS_KEY" >&2
    return 0
  fi
  for __pls_cand in "$__pls_root"/.github/workflows/*.yml "$__pls_root"/.github/workflows/*.yaml; do
    [[ -f "$__pls_cand" ]] || continue
    __pls_wf=""
    IFS= read -r -d '' __pls_wf <"$__pls_cand"
    [[ "$__pls_wf" =~ $__pls_re ]] || continue
    printf -v "$__pls_dest" %s "$__pls_cand"
    return 0
  done
}
