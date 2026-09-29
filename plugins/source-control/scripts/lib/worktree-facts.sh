# shellcheck shell=bash
# Worktree fact record for source-control. Sourced by the scripts; run directly
# with `list` to print the record (see the end of this file).
#
# One porcelain parse, one lock-reason codec, and one TSV row schema. Callers
# read WT_FACT_* after worktree_facts_parse_z. An empty column is `-`, applied
# once for every argument, so a new column cannot shift the row.

# worktree_lock_reason CREATOR [SESSION]
# CREATOR is the script name that arms the lock (worktree-create.sh or
# worktree-claim.sh). A session id emits `session <id> since`, which
# worktree_reason_is_ours matches. Without one, the reason names no session.
worktree_lock_reason() {
  local creator="$1" sid="${2:-}" host utc
  host="${HOSTNAME:-}"
  if [[ -z "$host" ]]; then
    host="$(hostname 2>/dev/null || printf 'unknown-host')"
  fi
  utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$sid" ]]; then
    printf '%s: lane active on %s session %s since %s; unlock when the owning lane is done' \
      "$creator" "$host" "$sid" "$utc"
  else
    printf '%s: lane active on %s since %s; unlock when the owning lane is done' \
      "$creator" "$host" "$utc"
  fi
}

# True when REASON names SID. Anchored on `session <sid> since` so s1 does not match s10.
worktree_reason_is_ours() {
  local reason="$1" sid="$2"
  [[ -n "$sid" && "$reason" == *"session ${sid} since"* ]]
}

# Decode a porcelain `locked` value. Quoted reasons drop the wrapping quotes
# and unescape \\ and \n.
worktree_decode_lock_reason() {
  local raw="$1"
  if [[ "$raw" == \"*\" ]]; then
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw//\\n/$'\n'}"
    raw="${raw//\\\\/\\}"
  fi
  printf '%s' "$raw"
}

# Read NUL-delimited `git worktree list --porcelain -z` from FILE.
# Fills WT_FACT_PATH, WT_FACT_HEAD, WT_FACT_BRANCH, WT_FACT_BARE (yes|no),
# WT_FACT_LOCKED (decoded reason, empty when unlocked or locked without one),
# WT_FACT_IS_LOCKED (yes|no, set for a reasonless lock too), WT_FACT_LINKED (yes|no), WT_FACT_PRUNABLE (yes|no).
# The first record consumes the main slot, including a bare hub, so a later
# linked worktree is never reported as the main checkout.
worktree_facts_parse_z() {
  local file="$1" line path="" head="" branch="" detached=0 bare=0 locked="" is_locked=no prunable=""
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
    WT_FACT_PATH+=("$path")
    WT_FACT_HEAD+=("$head")
    WT_FACT_BRANCH+=("$branch")
    if [[ "$bare" -eq 1 ]]; then
      WT_FACT_BARE+=("yes")
    else
      WT_FACT_BARE+=("no")
    fi
    WT_FACT_LOCKED+=("$locked")
    WT_FACT_IS_LOCKED+=("$is_locked")
    if [[ -n "$prunable" ]]; then
      WT_FACT_PRUNABLE+=("yes")
    else
      WT_FACT_PRUNABLE+=("no")
    fi
    path=""
    head=""
    branch=""
    detached=0
    bare=0
    locked=""
    is_locked=no
    prunable=""
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
    "bare") bare=1 ;;
    "locked")
      locked=""
      is_locked=yes
      ;;
    "locked "*)
      locked="$(worktree_decode_lock_reason "${line#locked }")"
      is_locked=yes
      ;;
    "prunable" | "prunable "*) prunable="yes" ;;
    *) ;;
    esac
  done <"$file"
  _worktree_facts_flush

  local i seen=0 linked
  if [[ ${#WT_FACT_PATH[@]} -eq 0 ]]; then
    return 0
  fi
  for i in "${!WT_FACT_PATH[@]}"; do
    if [[ "$seen" -eq 0 ]]; then
      linked="no"
      seen=1
    elif [[ "${WT_FACT_BARE[$i]}" == "yes" ]]; then
      linked="no"
    else
      linked="yes"
    fi
    WT_FACT_LINKED+=("$linked")
  done
}

# worktree_fact_row FIELD...
# Prints one TSV row. An empty field is `-`. The column count is the argument
# count, so adding a column cannot repeat a missing-fallback shift.
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

# Run directly: `bash worktree-facts.sh list [REPO_DIR]` prints a header and one
# row per worktree: path head branch bare linked locked lock_reason prunable.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ "${1:-}" == list ]] || {
    echo "usage: bash worktree-facts.sh list [REPO_DIR]" >&2
    exit 2
  }
  porcelain="$(mktemp)" || exit 4
  trap 'rm -f "$porcelain"' EXIT
  git -C "${2:-.}" worktree list --porcelain -z >"$porcelain" || {
    echo "error: git worktree list failed in ${2:-.}" >&2
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
