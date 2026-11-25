# shellcheck shell=bash
if ! declare -F slog_record_to >/dev/null 2>&1; then
  # shellcheck source=session-log-lib.sh
  source "${BASH_SOURCE[0]%/*}/session-log-lib.sh"
fi
# shellcheck source=hook-utils.sh
source "${BASH_SOURCE[0]%/*}/hook-utils.sh"

harness_ops::resolve_project_relative_dir() {
  local project_dir="$1" configured="$2" normalized segment candidate ancestor parent
  local -a segments

  [[ -n "$project_dir" && -n "$configured" ]] || return 1

  normalized="${configured//\\//}"
  [[ "$normalized" != /* ]] || return 1
  [[ ! "$normalized" =~ ^[A-Za-z]: ]] || return 1

  IFS='/' read -r -a segments <<<"$normalized"
  for segment in "${segments[@]}"; do
    [[ "$segment" != ".." ]] || return 1
  done

  project_dir="${project_dir%/}"
  candidate="${project_dir}/${normalized}"

  ancestor="$candidate"
  while [[ ! -e "$ancestor" && "$ancestor" != "/" && "$ancestor" != "." ]]; do
    parent=$(dirname -- "$ancestor")
    [[ "$parent" == "$ancestor" ]] && break # reached a root: dirname is a fixed point
    ancestor="$parent"
  done

  local physical_project="" physical_ancestor="" physical=""
  hook::physical_path_to physical "$project_dir" || :
  hook::normalize_path_to physical_project "$physical"
  physical_project="${physical_project%/}"
  hook::physical_path_to physical "$ancestor" || :
  hook::normalize_path_to physical_ancestor "$physical"
  if [[ "$physical_ancestor" != "$physical_project" && "$physical_ancestor" != "$physical_project"/* ]]; then
    return 1
  fi

  printf '%s' "$candidate"
}

harness_ops::repo_slug() {
  local p="" base hash physical=""
  hook::physical_path_to physical "$1" || :
  hook::normalize_path_to p "$physical"
  base="${p##*/}"
  base="${base//[^A-Za-z0-9._-]/-}"
  hash=$(printf '%s' "$p" | sha1sum 2>/dev/null | cut -c1-8)
  [[ -n "$hash" ]] || hash=$(printf '%s' "$p" | cksum 2>/dev/null | cut -d' ' -f1)
  printf '%s' "${base:-project}${hash:+-$hash}"
}

harness_ops::normalize_rel_segments() {
  local raw="${1//\\//}" out="" seg
  local -a segs
  IFS='/' read -r -a segs <<<"$raw"
  for seg in "${segs[@]}"; do
    [[ -z "$seg" || "$seg" == "." ]] && continue
    out+="${seg}/"
  done
  printf '%s' "${out%/}"
}

harness_ops::gitignore_escape() {
  local s="$1" out="" ch i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    # shellcheck disable=SC1003  # '\' is a literal single-backslash case pattern, not a botched quote escape
    case "$ch" in
    '*' | '?' | '[' | '\') out+='\' ;;
    *) ;;
    esac
    out+="$ch"
  done
  printf '%s' "$out"
}

harness_ops::resolve_skill_usage_dir() {
  local scope="$1" project_dir="$2" rel_dir="$3"
  case "$scope" in
  user)
    [[ -n "${HOME:-}" && -d "${HOME:-}" ]] || return 2
    harness_ops::resolve_project_relative_dir "$HOME" "$rel_dir"
    ;;
  data-dir)
    [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] || return 2
    printf '%s' "${CLAUDE_PLUGIN_DATA%/}/skill-usage/$(harness_ops::repo_slug "$project_dir")"
    ;;
  *)
    harness_ops::resolve_project_relative_dir "$project_dir" "$rel_dir"
    ;;
  esac
}

harness_ops::ensure_git_exclude() {
  local project_dir="$1" rel_dir="$2" store_file="${3:-skill-usage.jsonl}" exclude_file dir line
  [[ "${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_GIT_EXCLUDE:-true}" == "true" ]] || return 0
  exclude_file=$(git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$project_dir" rev-parse --git-path info/exclude 2>/dev/null | tr -d '\r')
  [[ -n "$exclude_file" ]] || return 0
  case "$exclude_file" in
  /* | [A-Za-z]:*) ;;
  *) exclude_file="${project_dir%/}/$exclude_file" ;;
  esac
  dir="$(harness_ops::normalize_rel_segments "$rel_dir")"
  if [[ -n "$dir" ]]; then
    line="/$(harness_ops::gitignore_escape "$dir")/"
  else
    line="/$(harness_ops::gitignore_escape "$store_file")*"
  fi
  if [[ -f "$exclude_file" ]] && grep -qxF -- "$line" "$exclude_file" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$(dirname -- "$exclude_file")" 2>/dev/null || return 0
  printf '%s\n' "$line" >>"$exclude_file" 2>/dev/null || true
}

harness_ops::record_skill_use() {
  local hook_event="$1" notice_prefix="$2" input="$3" skill="$4" src="$5" exp_type="$6"
  local project_dir="" rel_dir scope log_dir verified_log_dir ts branch line=""
  local -a exp_keys=()
  hook::repo_root_to project_dir "${CLAUDE_PROJECT_DIR:-.}" || :
  rel_dir="${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR:-.claude/observability}"
  scope="${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE:-repo}"
  case "$scope" in
  repo | user | data-dir) ;;
  *)
    if hook::notice_once "${notice_prefix}-badscope" "$input"; then
      hook::emit_skip_notice "$hook_event" "" \
        "session-telemetry skill-usage logging: unknown skill_usage_scope \"${scope}\" (valid: repo, user, data-dir) — using the default repo scope."
    fi
    scope="repo"
    ;;
  esac
  if ! log_dir=$(harness_ops::resolve_skill_usage_dir "$scope" "$project_dir" "$rel_dir"); then
    if hook::notice_once "${notice_prefix}-badconfig" "$input"; then
      if [[ "$scope" == "data-dir" ]]; then
        hook::emit_skip_notice "$hook_event" "" \
          "session-telemetry: skill-usage logging skipped: scope \"data-dir\" needs CLAUDE_PLUGIN_DATA, which is not set."
      else
        hook::emit_skip_notice "$hook_event" "" \
          "session-telemetry: skill-usage logging skipped: skill_usage_dir is not a contained relative path for scope \"${scope}\". /plugin configure session-telemetry fixes it."
      fi
    fi
  elif mkdir -p "$log_dir" 2>/dev/null &&
    verified_log_dir=$(harness_ops::resolve_skill_usage_dir "$scope" "$project_dir" "$rel_dir") &&
    [[ "$verified_log_dir" == "$log_dir" ]]; then
    [[ "$scope" == "repo" ]] && harness_ops::ensure_git_exclude "$project_dir" "$rel_dir"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)
    branch=$(hook::git_untrusted -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="unknown"
    branch="${branch//$'\r'/}"
    [[ -n "$exp_type" ]] && exp_keys=(expansion_type s "$exp_type")
    slog_record_to line \
      ts s "$ts" \
      event s "SkillUse" \
      skill s "$skill" \
      branch s "$branch" \
      project s "$(basename -- "$project_dir")" \
      project_id s "$(harness_ops::repo_slug "$project_dir")" \
      hook s "skill-usage-audit" \
      source s "$src" \
      ${exp_keys[@]+"${exp_keys[@]}"}
    slog_append_capped "${log_dir}/skill-usage.jsonl" "$line" "${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_MAX_BYTES:-}"
  else
    if hook::notice_once "${notice_prefix}-nodest" "$input"; then
      hook::emit_skip_notice "$hook_event" "" \
        "session-telemetry: skill-usage logging skipped: the configured destination could not be created safely."
    fi
  fi
}
