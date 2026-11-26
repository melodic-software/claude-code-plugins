# shellcheck shell=bash

worktree_host_name() {
  local host="${HOSTNAME:-}"
  [[ -n "$host" ]] || host="$(hostname 2>/dev/null || printf 'unknown-host')"
  printf '%s' "$host"
}

worktree_lock_reason() {
  local creator="$1" sid="${2:-}" host utc
  host="$(worktree_host_name)"
  utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$sid" ]]; then
    printf '%s: lane active on %s session %s since %s; unlock when the owning lane is done' \
      "$creator" "$host" "$sid" "$utc"
  else
    printf '%s: lane active on %s since %s; unlock when the owning lane is done' \
      "$creator" "$host" "$utc"
  fi
}

worktree_reason_is_ours() {
  local reason="$1" sid="$2"
  [[ -n "$sid" && "$reason" == *"session ${sid} since"* ]]
}

worktree_reason_lane() {
  local re='lane active on ([^ ]+) session ([A-Za-z0-9._:-]+) since'
  [[ "$1" =~ $re ]] || return 1
  printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

WORKTREE_LIST_Z_GIT_FLOOR="2.36.0"
worktree_list_z_floor_note() {
  printf 'worktree list -z needs git >= %s; installed: %s' \
    "$WORKTREE_LIST_Z_GIT_FLOOR" "$(git --version 2>/dev/null || printf 'git not found')"
}

worktree_facts_parse_z() {
  local file="$1" line path="" head="" branch="" detached=0 bare=no locked="" is_locked=no prunable=no
  WT_FACT_PATH=()
  WT_FACT_HEAD=()
  WT_FACT_BRANCH=()
  WT_FACT_BARE=()
  WT_FACT_LOCKED=()
  WT_FACT_IS_LOCKED=()
  WT_FACT_LINKED=()
  WT_FACT_PRUNABLE=()

  _worktree_facts_flush() {
    [[ -n "$path" ]] || return 0
    [[ "$detached" -eq 1 ]] && branch="(detached)"
    if [[ ${#WT_FACT_PATH[@]} -eq 0 || "$bare" == yes ]]; then
      WT_FACT_LINKED+=("no")
    else
      WT_FACT_LINKED+=("yes")
    fi
    WT_FACT_PATH+=("$path")
    WT_FACT_HEAD+=("$head")
    WT_FACT_BRANCH+=("$branch")
    WT_FACT_BARE+=("$bare")
    WT_FACT_LOCKED+=("$locked")
    WT_FACT_IS_LOCKED+=("$is_locked")
    WT_FACT_PRUNABLE+=("$prunable")
    path="" head="" branch="" detached=0 bare=no locked="" is_locked=no prunable=no
  }

  while IFS= read -r -d '' line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    case "$line" in
    "worktree "*)
      _worktree_facts_flush
      path="${line#worktree }"
      ;;
    "HEAD "*) head="${line#HEAD }" ;;
    "branch "*) branch="${line#branch refs/heads/}" ;;
    "detached") detached=1 ;;
    "bare") bare=yes ;;
    "locked")
      locked=""
      is_locked=yes
      ;;
    "locked "*)
      locked="${line#locked }"
      is_locked=yes
      ;;
    "prunable" | "prunable "*) prunable=yes ;;
    *) ;;
    esac
  done <"$file"
  _worktree_facts_flush
}

worktree_fact_row() {
  local -a cols=()
  local field
  for field in "$@"; do
    [[ -n "$field" ]] || field="-"
    cols+=("$field")
  done
  local IFS=$'\t'
  printf '%s\n' "${cols[*]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ "${1:-}" == list ]] || {
    echo "usage: bash worktree-facts.sh list [REPO_DIR]" >&2
    exit 2
  }
  porcelain="$(mktemp)" || exit 4
  trap 'rm -f "$porcelain"' EXIT
  git -C "${2:-.}" worktree list --porcelain -z >"$porcelain" || {
    echo "error: git worktree list failed in ${2:-.} ($(worktree_list_z_floor_note))" >&2
    exit 4
  }
  worktree_facts_parse_z "$porcelain"
  worktree_fact_row path head branch bare linked locked lock_reason prunable
  for i in "${!WT_FACT_PATH[@]}"; do
    worktree_fact_row "${WT_FACT_PATH[$i]}" "${WT_FACT_HEAD[$i]}" "${WT_FACT_BRANCH[$i]}" \
      "${WT_FACT_BARE[$i]}" "${WT_FACT_LINKED[$i]}" "${WT_FACT_IS_LOCKED[$i]}" \
      "${WT_FACT_LOCKED[$i]}" "${WT_FACT_PRUNABLE[$i]}"
  done
fi
