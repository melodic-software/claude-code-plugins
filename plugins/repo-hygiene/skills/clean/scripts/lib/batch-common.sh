# shellcheck shell=bash
# shellcheck disable=SC2034 # BATCH_ARG_ERROR is read by the sourcing scripts

# shellcheck source=clean-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/clean-common.sh"

batch_normalize_input() {
  local v="${1%$'\r'}"
  v="${v//\\//}"
  while [[ "$v" == */ && "$v" != "/" ]]; do v="${v%/}"; done
  printf '%s' "$v"
}

batch_read_lines_into() {
  local -n _dest="$1"
  local src="$2" line
  if [[ "$src" == "-" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -n "$line" ]] && _dest+=("$line")
    done
    return 0
  fi
  [[ -f "$src" ]] || return 1
  # A {fd} redirection allocates a descriptor of 10 or higher, which ulimit -n 10 refuses, so fd 3 is fixed:
  # https://www.gnu.org/software/bash/manual/html_node/Redirections.html
  exec 3<"$src" || return 1
  while IFS= read -r -u 3 line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "$line" ]] && _dest+=("$line")
  done
  exec 3<&-
  return 0
}

BATCH_SKIP_INPUTS=()
BATCH_SKIP_HITS=()
BATCH_SKIP_MATCHED=""

batch_reset_skip_hits() {
  local s
  BATCH_SKIP_HITS=()
  for ((s = 0; s < ${#BATCH_SKIP_INPUTS[@]}; s++)); do BATCH_SKIP_HITS+=(0); done
}

batch_skip_match() {
  local repo_key="$1" s
  BATCH_SKIP_MATCHED=""
  for ((s = 0; s < ${#BATCH_SKIP_INPUTS[@]}; s++)); do
    if clean_skip_matches "$repo_key" "${BATCH_SKIP_INPUTS[$s]}"; then
      BATCH_SKIP_MATCHED="${BATCH_SKIP_INPUTS[$s]}"
      BATCH_SKIP_HITS[s]=1
    fi
  done
  [[ -n "$BATCH_SKIP_MATCHED" ]]
}

batch_report_unmatched_skips() {
  local s
  for ((s = 0; s < ${#BATCH_SKIP_INPUTS[@]}; s++)); do
    if [[ "${BATCH_SKIP_HITS[$s]}" -eq 0 ]]; then
      printf 'UnmatchedSkip: %s\n' "${BATCH_SKIP_INPUTS[$s]}"
    fi
  done
}

BATCH_TOPS=()
BATCH_KEYS=()
BATCH_INVALID=()
BATCH_INVALID_REASONS=()
BATCH_DUPS=()
BATCH_DUP_OF=()

batch_resolve_repos() {
  BATCH_TOPS=()
  BATCH_KEYS=()
  BATCH_INVALID=()
  BATCH_INVALID_REASONS=()
  BATCH_DUPS=()
  BATCH_DUP_OF=()
  local input norm top key
  local -A seen_keys=()
  for input in "$@"; do
    [[ -n "$input" ]] || continue
    norm="$(batch_normalize_input "$input")"
    [[ -n "$norm" ]] || continue
    if [[ ! -d "$norm" ]]; then
      BATCH_INVALID+=("$input")
      BATCH_INVALID_REASONS+=("not-a-directory")
      continue
    fi
    top="$(git -C "$norm" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
    if [[ -z "$top" ]]; then
      BATCH_INVALID+=("$input")
      BATCH_INVALID_REASONS+=("not-a-git-repo")
      continue
    fi
    key="$(clean_path_key "$top")"
    [[ -n "${seen_keys[$key]:-}" ]] && continue
    seen_keys["$key"]=1
    BATCH_TOPS+=("$top")
    BATCH_KEYS+=("$key")
  done
}

batch_remote_key() {
  local u scp=1 host rest
  u="$(git -C "$1" remote get-url origin 2>/dev/null | tr -d '\r')"
  [[ -n "$u" ]] || return 0
  [[ "$u" == *://* ]] && scp=0
  u="${u#*://}"
  u="${u#*@}"
  [[ $scp -eq 1 && "$u" =~ ^[^/:]+: ]] && u="${u/:/\/}"
  u="${u%/}"
  u="${u%.git}"
  host="$(tr '[:upper:]' '[:lower:]' <<<"${u%%/*}")"
  rest="${u#"${u%%/*}"}"
  [[ "$host" == github.com ]] && rest="$(tr '[:upper:]' '[:lower:]' <<<"$rest")"
  printf '%s%s' "$host" "$rest"
}

batch_is_skip_listed() {
  local s
  for ((s = 0; s < ${#BATCH_SKIP_INPUTS[@]}; s++)); do
    clean_skip_matches "$1" "${BATCH_SKIP_INPUTS[$s]}" && return 0
  done
  return 1
}

batch_dedupe_clones() {
  local i top rk kept_top common kept_common
  local -A first=()
  local -a tops=() keys=()
  BATCH_DUPS=()
  BATCH_DUP_OF=()
  for ((i = 0; i < ${#BATCH_TOPS[@]}; i++)); do
    top="${BATCH_TOPS[$i]}"
    if batch_is_skip_listed "${BATCH_KEYS[$i]}"; then
      tops+=("$top")
      keys+=("${BATCH_KEYS[$i]}")
      continue
    fi
    rk="$(batch_remote_key "$top")"
    if [[ -n "$rk" && -n "${first[$rk]:-}" ]]; then
      kept_top="${first[$rk]}"
      common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
      kept_common="$(git -C "$kept_top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
      if [[ -z "$common" || "$common" != "$kept_common" ]]; then
        BATCH_DUPS+=("$top")
        BATCH_DUP_OF+=("$kept_top")
        continue
      fi
    fi
    [[ -n "$rk" && -z "${first[$rk]:-}" ]] && first["$rk"]="$top"
    tops+=("$top")
    keys+=("${BATCH_KEYS[$i]}")
  done
  BATCH_TOPS=("${tops[@]}")
  BATCH_KEYS=("${keys[@]}")
}

batch_emit_dups() {
  local i
  for ((i = 0; i < ${#BATCH_DUPS[@]}; i++)); do
    batch_emit "${BATCH_DUPS[$i]}" skipped "skipped duplicate of ${BATCH_DUP_OF[$i]}"
  done
  return 0
}

batch_discover_fleet() {
  local -n _fleet="$1"
  local src
  if command -v ghq >/dev/null 2>&1; then
    batch_read_lines_into _fleet - < <(ghq list -p 2>/dev/null)
  fi
  if command -v chezmoi >/dev/null 2>&1; then
    src="$(chezmoi source-path 2>/dev/null | tr -d '\r')"
    if [[ -n "$src" && -d "$src" ]] && git -C "$src" rev-parse --show-toplevel >/dev/null 2>&1; then
      _fleet+=("$src")
    fi
  fi
}

batch_discover_owner() {
  local -n _owned="$1"
  local owner="$2" entry top rk path
  local -a found=()
  batch_discover_fleet found
  for entry in "${found[@]}"; do
    top="$(batch_normalize_input "$entry")"
    rk="$(batch_remote_key "$top")"
    [[ -n "$rk" && -n "${rk%%/*}" ]] || continue
    path="${rk#*/}"
    if [[ "${rk%%/*}" == github.com ]]; then
      owner="$(tr '[:upper:]' '[:lower:]' <<<"$2")"
    else
      owner="$2"
    fi
    [[ "${path%%/*}" == "$owner" && "$path" == */* ]] && _owned+=("$entry")
  done
  return 0
}

BATCH_GITDIR_KEYS=()
BATCH_GITDIR_TOPS=()

batch_reset_gitdirs() {
  BATCH_GITDIR_KEYS=()
  BATCH_GITDIR_TOPS=()
}

batch_add_gitdir() {
  local top="$1" common key e
  common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
  if [[ -z "$common" ]]; then
    common="$(git -C "$top" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
    [[ -n "$common" && "$common" != /* && "$common" != ?:/* ]] && common="$top/$common"
  fi
  [[ -n "$common" ]] || return 1
  key="$(clean_path_key "$common")"
  for e in "${BATCH_GITDIR_KEYS[@]}"; do
    [[ "$e" == "$key" ]] && return 2
  done
  BATCH_GITDIR_KEYS+=("$key")
  BATCH_GITDIR_TOPS+=("$top")
  return 0
}

batch_emit() {
  printf 'Repo: %s\n' "$1"
  printf 'Outcome: %s\n' "$2"
  printf 'Reason: %s\n' "$3"
  printf '%s\n' '---'
}

BATCH_REPO_INPUTS=()
BATCH_ARG_SHIFT=0
BATCH_ARG_ERROR=""

batch_take_selection_arg() {
  local flag="$1"
  BATCH_ARG_SHIFT=1
  shift
  case "$flag" in
  --repo)
    if [[ $# -lt 1 || "$1" == -* ]]; then
      BATCH_ARG_ERROR="--repo requires a directory"
      return 1
    fi
    while [[ $# -gt 0 && "$1" != -* ]]; do
      BATCH_REPO_INPUTS+=("$1")
      BATCH_ARG_SHIFT=$((BATCH_ARG_SHIFT + 1))
      shift
    done
    ;;
  --repos-from | --skip | --skip-from)
    if [[ $# -lt 1 ]]; then
      BATCH_ARG_ERROR="$flag requires a value"
      return 1
    fi
    BATCH_ARG_SHIFT=2
    if [[ "$flag" == --skip ]]; then
      BATCH_SKIP_INPUTS+=("$1")
      return 0
    fi
    local dest=BATCH_REPO_INPUTS
    [[ "$flag" == --skip-from ]] && dest=BATCH_SKIP_INPUTS
    batch_read_lines_into "$dest" "$1" || {
      BATCH_ARG_ERROR="file not found: $1"
      return 1
    }
    ;;
  *)
    BATCH_ARG_ERROR="not a selection flag: $flag"
    return 1
    ;;
  esac
}

batch_run_fleet() {
  local script="$1" i top out rc audited=0 skipped=0 dup=0 failed=0 blocked=0
  shift
  batch_reset_skip_hits
  batch_reset_gitdirs
  for ((i = 0; i < ${#BATCH_TOPS[@]}; i++)); do
    top="${BATCH_TOPS[$i]}"
    printf 'Progress: %s/%s %s\n' "$((i + 1))" "${#BATCH_TOPS[@]}" "$top" >&2
    if batch_skip_match "${BATCH_KEYS[$i]}"; then
      batch_emit "$top" skipped "skip-list ($BATCH_SKIP_MATCHED)"
      skipped=$((skipped + 1))
      continue
    fi
    batch_add_gitdir "$top"
    if [[ $? -eq 2 ]]; then
      batch_emit "$top" skipped "shares a git common dir with an audited repo"
      dup=$((dup + 1))
      continue
    fi
    out="$(cd "$top" && bash "$script" "$@")"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      batch_emit "$top" failed "audit exited $rc"
      printf '%s\n' "$out" >&2
      failed=$((failed + 1))
      continue
    fi
    printf 'Repo: %s\n%s\n%s\n' "$top" "$out" '---'
    audited=$((audited + 1))
  done
  batch_emit_dups
  dup=$((dup + ${#BATCH_DUPS[@]}))
  for ((i = 0; i < ${#BATCH_INVALID[@]}; i++)); do
    batch_emit "${BATCH_INVALID[$i]}" blocked "${BATCH_INVALID_REASONS[$i]}"
    blocked=$((blocked + 1))
  done
  batch_report_unmatched_skips
  printf 'FleetSummary: repos=%s audited=%s skipped=%s duplicate=%s blocked=%s failed=%s\n' \
    "$((${#BATCH_TOPS[@]} + ${#BATCH_DUPS[@]} + blocked))" "$audited" "$skipped" "$dup" "$blocked" "$failed"
  return 0
}
