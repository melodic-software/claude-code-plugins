#!/usr/bin/env bash
# Read-only cross-repository Git/GitHub hygiene collector.
# Intentionally contains no apply mode and no mutating Git/GitHub operation.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: audit-fleet.sh [--root DIR]... [--repo DIR]... [--config FILE]
                      [--canonical github.com/owner/repo=PATH]...
                      [--max-depth 1..12]

Read-only. Discovers repositories, resolves optional canonical checkouts, and
reports confidence-tiered branch, worktree, and GitHub-identity findings.
EOF
}

fail() {
  printf 'Error: ' >&2
  display_value "$*" >&2
  printf '\n' >&2
  exit 2
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Keep ordinary printable report values readable, but encode any control-bearing value as one Bash
# %q field. Git permits newlines and terminal-control bytes in filesystem paths; raw rendering would
# let a crafted registration forge Finding/Confidence/Handoff lines in this actionable report.
display_value() {
  local value="$1" escaped
  local LC_ALL=C
  if [[ "$value" =~ ^[[:print:]]*$ ]]; then
    printf '%s' "$value"
  else
    printf -v escaped '%q' "$value"
    printf '%s' "$escaped"
  fi
}

print_field() {
  local label="$1" value="$2"
  printf '%s: ' "$label"
  display_value "$value"
  printf '\n'
}

# Fail closed before executing either external state reader. The allowlists constrain command,
# option order, arity, and dynamic operand shape; caller-controlled global options, aliases, config
# injection, write-capable API methods, and all other Git/gh subcommands are rejected.
git_probe_allowed() {
  local key remote ref
  case "${1:-}" in
  config)
    [[ "${2:-}" == "--file" && -n "${3:-}" ]] || return 1
    if [[ $# -eq 4 && "$4" == "--list" ]]; then
      return 0
    fi
    if [[ $# -eq 5 && "$4" == "--get" ]]; then
      key="$5"
      [[ "$key" == "fleet.maxDepth" || "$key" =~ ^canonical\.github\.com/[^/[:cntrl:]]+/[^/[:cntrl:]]+\.path$ ]]
      return
    fi
    if [[ $# -eq 6 && "$4" == "--null" && "$5" == "--get-all" ]]; then
      [[ "$6" == "fleet.root" || "$6" == "fleet.repo" ]]
      return
    fi
    if [[ $# -eq 6 && "$4" == "--get-regexp" && "$5" == "-z" ]]; then
      # Fixed literal pattern only -- not an arbitrary caller-supplied regex.
      [[ "$6" == '^canonical\.[^[:cntrl:]]+\.path$' ]]
      return
    fi
    return 1
    ;;
  -C)
    [[ $# -ge 4 && -n "${2:-}" ]] || return 1
    case "$3" in
    rev-parse)
      [[ $# -eq 4 && "$4" == "--show-toplevel" ]] ||
        [[ $# -eq 5 && "$4" == "--path-format=absolute" && "$5" == "--git-common-dir" ]]
      ;;
    remote)
      if [[ $# -eq 3 ]]; then
        return 0
      fi
      remote="${5:-}"
      [[ $# -eq 5 && "$4" == "get-url" && -n "$remote" && "$remote" != -* &&
        ! "$remote" =~ [[:cntrl:][:space:]] ]]
      ;;
    worktree)
      [[ $# -eq 7 && "$4" == "list" && "$5" == "--porcelain" && "$6" == "-z" && "$7" == "--" ]]
      ;;
    symbolic-ref)
      ref="${4:-}"
      [[ $# -eq 4 && "$ref" == refs/remotes/*/HEAD && ! "$ref" =~ [[:cntrl:][:space:]] ]]
      ;;
    branch)
      [[ $# -eq 4 && "$4" == "--show-current" ]]
      ;;
    for-each-ref)
      [[ $# -eq 6 && "$4" == "--format=%(refname:short)%09%(objectname)%00" && "$5" == "--" ]] || return 1
      [[ "$6" == "refs/heads/" ]] && return 0
      [[ "$6" == refs/remotes/*/ && ! "$6" =~ [[:cntrl:][:space:]] ]]
      ;;
    merge-base)
      ref="${6:-}"
      [[ $# -eq 6 && "$4" == "--is-ancestor" && -n "${5:-}" && "${5:-}" != -* &&
        ! "${5:-}" =~ [[:cntrl:][:space:]] && "$ref" == refs/remotes/* &&
        ! "$ref" =~ [[:cntrl:][:space:]] ]]
      ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

run_git_probe() {
  if ! git_probe_allowed "$@"; then
    printf 'Rejected non-allowlisted Git probe\n' >&2
    return 126
  fi
  (
    # Repository selectors and command-scoped config must come only from the validated argv above.
    # GIT_CONFIG_COUNT=0 neutralizes inherited GIT_CONFIG_KEY_*/VALUE_* pairs even when the parent
    # environment contains them; the older aggregate injection variable is removed explicitly.
    # GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM are pinned to /dev/null (per git(1) ENVIRONMENT) so an
    # inherited selector or a global includeIf (e.g. an injected url.*.insteadOf) can never redirect
    # a probe away from the repository's own on-disk config.
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_PREFIX
    export GIT_CONFIG_COUNT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      GIT_NO_LAZY_FETCH=1 GIT_OPTIONAL_LOCKS=0 GIT_PAGER=cat GIT_TERMINAL_PROMPT=0
    command git "$@"
  )
}

gh_probe_allowed() {
  case "${1:-}" in
  auth)
    [[ $# -eq 4 && "$2" == "status" && "$3" == "--hostname" && "$4" == "github.com" ]]
    ;;
  api)
    [[ $# -eq 8 && "$2" =~ ^repos/[^/[:cntrl:][:space:]]+/[^/[:cntrl:][:space:]]+$ &&
      "$3" == "--hostname" && "$4" == "github.com" && "$5" == "--method" && "$6" == "GET" &&
      "$7" == "--template" && "$8" == '{{printf "%s\t%s" .full_name .default_branch}}' ]]
    ;;
  pr)
    [[ "${2:-}" == "list" && "${3:-}" == "--repo" &&
      "${4:-}" =~ ^github\.com/[^/[:cntrl:][:space:]]+/[^/[:cntrl:][:space:]]+$ &&
      "${5:-}" == "--state" && "${6:-}" == "merged" ]] || return 1
    if [[ $# -eq 12 ]]; then
      [[ "$7" == "--limit" && "$8" == "200" && "$9" == "--json" &&
        "${10}" == "number,headRefName,headRefOid,mergedAt,url" && "${11}" == "--template" &&
        "${12}" == '{{range .}}{{printf "%v\t%s\t%s\t%s\t%s\n" .number .headRefName .headRefOid .mergedAt .url}}{{end}}' ]]
      return
    fi
    [[ $# -eq 14 && "$7" == "--head" && -n "$8" && "$8" != -* &&
      ! "$8" =~ [[:cntrl:]] && "$9" == "--limit" && "${10}" == "100" &&
      "${11}" == "--json" && "${12}" == "number,headRefName,headRefOid,mergedAt,url" &&
      "${13}" == "--template" &&
      "${14}" == '{{range .}}{{printf "%v\t%s\t%s\t%s\t%s\n" .number .headRefName .headRefOid .mergedAt .url}}{{end}}' ]]
    ;;
  *) return 1 ;;
  esac
}

# GitHub CLI has no request-timeout flag. Prefer GNU timeout/gtimeout only when its documented
# --kill-after capability is present. The pure-Bash watchdog is the platform-safe fallback and still
# escalates TERM to KILL after a finite grace period. The test switch can only shorten both bounds.
GH_TIMEOUT_SECONDS=30
GH_KILL_AFTER_SECONDS=5
if [[ "${REPO_FLEET_TEST_FAST_TIMEOUTS:-}" == "1" ]]; then
  GH_TIMEOUT_SECONDS=1
  GH_KILL_AFTER_SECONDS=1
fi
GH_TIMEOUT_COMMAND=""
if [[ "${REPO_FLEET_FORCE_BASH_TIMEOUT:-}" != "1" ]]; then
  for candidate in timeout gtimeout; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" --help 2>&1 | grep -Fq -- '--kill-after'; then
      GH_TIMEOUT_COMMAND="$candidate"
      break
    fi
  done
fi

run_with_bash_timeout() {
  local child watchdog status
  "$@" &
  child=$!
  (
    sleep "$GH_TIMEOUT_SECONDS"
    kill -TERM "$child" 2>/dev/null || exit 0
    sleep "$GH_KILL_AFTER_SECONDS"
    kill -KILL "$child" 2>/dev/null || true
  ) &
  watchdog=$!
  wait "$child"
  status=$?
  kill -TERM "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$status"
}

run_bounded_gh() {
  if ! gh_probe_allowed "$@"; then
    printf 'Rejected non-allowlisted gh probe\n' >&2
    return 126
  fi
  (
    unset GH_REPO GH_DEBUG DEBUG GH_FORCE_TTY GH_PAGER PAGER GH_EDITOR GIT_EDITOR VISUAL EDITOR \
      GH_BROWSER BROWSER
    export GH_HOST=github.com GH_PROMPT_DISABLED=1 GH_TELEMETRY=false GH_NO_UPDATE_NOTIFIER=1 \
      GH_NO_EXTENSION_UPDATE_NOTIFIER=1 GH_SPINNER_DISABLED=1 NO_COLOR=1
    if [[ -n "$GH_TIMEOUT_COMMAND" ]]; then
      "$GH_TIMEOUT_COMMAND" --signal=TERM --kill-after="${GH_KILL_AFTER_SECONDS}s" \
        "${GH_TIMEOUT_SECONDS}s" gh "$@"
    else
      run_with_bash_timeout gh "$@"
    fi
  )
}

# Tests source these fail-closed wrappers directly to exercise forbidden Git/gh vectors without
# running discovery. Normal execution continues into the collector below.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

command -v git >/dev/null 2>&1 || fail "git is required"

CASE_INSENSITIVE_PATHS=false
case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*) CASE_INSENSITIVE_PATHS=true ;;
*) ;;
esac

ROOT_ARGS=()
REPO_ARGS=()
OVERRIDE_KEYS=()
OVERRIDE_PATHS=()
CONFIG_FILE=""
MAX_DEPTH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -ge 2 ]] || fail "--root requires a directory"
    ROOT_ARGS+=("$2")
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || fail "--repo requires a directory"
    REPO_ARGS+=("$2")
    shift 2
    ;;
  --config)
    [[ $# -ge 2 ]] || fail "--config requires a file"
    [[ -z "$CONFIG_FILE" ]] || fail "--config may be supplied only once"
    CONFIG_FILE="$2"
    shift 2
    ;;
  --canonical)
    [[ $# -ge 2 ]] || fail "--canonical requires github.com/owner/repo=PATH"
    pair="$2"
    [[ "$pair" == *=* ]] || fail "invalid --canonical value: $pair"
    key="${pair%%=*}"
    value="${pair#*=}"
    key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
    [[ "$key" =~ ^github\.com/[^/]+/[^/]+$ && -n "$value" ]] ||
      fail "invalid --canonical value: $pair"
    OVERRIDE_KEYS+=("$key")
    OVERRIDE_PATHS+=("$value")
    shift 2
    ;;
  --max-depth)
    [[ $# -ge 2 ]] || fail "--max-depth requires an integer"
    MAX_DEPTH="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) fail "unknown argument: $1" ;;
  esac
done

# Config resolution ladder: explicit --config, then the project-scoped file,
# then the user-global one. A fleet config is inherently machine-scoped, so a
# user-global ~/.claude file is honored when the current project carries none —
# that file is recorded user intent, not a guessed broader machine root. The
# consumed source is named in the report header so silent non-consumption
# cannot happen.
CONFIG_SOURCE="none"
if [[ -n "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" ]] || fail "config file not found: $CONFIG_FILE"
  CONFIG_SOURCE="explicit --config"
else
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -f "${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf" ]]; then
    CONFIG_FILE="${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf"
    CONFIG_SOURCE="project"
  else
    home_dir="${HOME:-${USERPROFILE:-}}"
    if [[ -n "$home_dir" && -f "$home_dir/.claude/repo-fleet-hygiene.conf" ]]; then
      CONFIG_FILE="$home_dir/.claude/repo-fleet-hygiene.conf"
      CONFIG_SOURCE="user-global"
    fi
  fi
fi
if [[ -n "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" 2>/dev/null && pwd -P)/$(basename "$CONFIG_FILE")"
  # An invalid config fails loud regardless of how it was found — an
  # auto-probed file never silently falls back to a narrower scope.
  run_git_probe config --file "$CONFIG_FILE" --list >/dev/null 2>&1 || fail "invalid Git config: $CONFIG_FILE"
  CONFIG_DIR="$(dirname "$CONFIG_FILE")"
else
  CONFIG_DIR=""
fi

if [[ -z "$MAX_DEPTH" && -n "$CONFIG_FILE" ]]; then
  MAX_DEPTH="$(run_git_probe config --file "$CONFIG_FILE" --get fleet.maxDepth 2>/dev/null || true)"
fi
MAX_DEPTH="${MAX_DEPTH:-5}"
[[ "$MAX_DEPTH" =~ ^[0-9]+$ && "$MAX_DEPTH" -ge 1 && "$MAX_DEPTH" -le 12 ]] ||
  fail "max depth must be an integer from 1 through 12"

resolve_input_path() {
  local value="$1" base="$2"
  if [[ "$value" =~ ^/ || "$value" =~ ^[A-Za-z]:[\\/] ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$base" "$value"
  fi
}

if [[ -n "$CONFIG_FILE" ]]; then
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] && ROOT_ARGS+=("$(resolve_input_path "$value" "$CONFIG_DIR")")
  done < <(run_git_probe config --file "$CONFIG_FILE" --null --get-all fleet.root 2>/dev/null || true)
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] && REPO_ARGS+=("$(resolve_input_path "$value" "$CONFIG_DIR")")
  done < <(run_git_probe config --file "$CONFIG_FILE" --null --get-all fleet.repo 2>/dev/null || true)
fi

if [[ ${#ROOT_ARGS[@]} -eq 0 && ${#REPO_ARGS[@]} -eq 0 ]]; then
  REPO_ARGS+=("${CLAUDE_PROJECT_DIR:-$PWD}")
fi

path_key() {
  local value="${1//\\//}"
  while [[ "$value" == */ ]]; do value="${value%/}"; done
  if [[ "$CASE_INSENSITIVE_PATHS" == "true" ]]; then
    lower "$value"
  else
    printf '%s' "$value"
  fi
}

TARGETS=()
TARGET_COMMON_KEYS=()
add_target() {
  local candidate="$1" top common common_key existing
  [[ -d "$candidate" ]] || fail "repository directory not found: $candidate"
  top="$(run_git_probe -C "$candidate" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" ||
    fail "not a Git working tree: $candidate"
  common="$(run_git_probe -C "$candidate" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')" ||
    fail "cannot resolve Git common directory: $candidate"
  common_key="$(path_key "$common")"
  for existing in "${TARGET_COMMON_KEYS[@]:-}"; do
    [[ "$existing" == "$common_key" ]] && return 0
  done
  TARGETS+=("$top")
  TARGET_COMMON_KEYS+=("$common_key")
}

for repo in "${REPO_ARGS[@]:-}"; do
  [[ -n "$repo" ]] && add_target "$repo"
done

discover_repositories() {
  local dir="$1" depth="$2" child name
  [[ -d "$dir" && ! -L "$dir" ]] || return 0
  if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
    add_target "$dir"
    return 0
  fi
  [[ "$depth" -lt "$MAX_DEPTH" ]] || return 0
  for child in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -d "$child" && ! -L "$child" ]] || continue
    name="$(basename "$child")"
    case "$name" in
    . | .. | .git | node_modules | vendor | .venv) continue ;;
    *) discover_repositories "$child" $((depth + 1)) ;;
    esac
  done
}

for root in "${ROOT_ARGS[@]:-}"; do
  [[ -n "$root" ]] || continue
  [[ -d "$root" ]] || fail "discovery root not found: $root"
  discover_repositories "$root" 0
done

[[ ${#TARGETS[@]} -gt 0 ]] || fail "no Git working trees found in the requested scope"

GH_READY=false
if command -v gh >/dev/null 2>&1 && run_bounded_gh auth status --hostname github.com >/dev/null 2>&1; then
  GH_READY=true
fi

select_remote() {
  local repo="$1" remotes count
  if run_git_probe -C "$repo" remote get-url origin >/dev/null 2>&1; then
    SELECTED_REMOTE="origin"
  else
    remotes="$(run_git_probe -C "$repo" remote 2>/dev/null | tr -d '\r')"
    count="$(printf '%s\n' "$remotes" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$count" == "1" ]]; then
      SELECTED_REMOTE="$(printf '%s\n' "$remotes" | sed '/^$/d')"
    else
      SELECTED_REMOTE=""
      return 1
    fi
  fi
  SELECTED_URL="$(run_git_probe -C "$repo" remote get-url "$SELECTED_REMOTE" 2>/dev/null | tr -d '\r')" || return 1
}

parse_github_url() {
  local url="$1" rest authority path host
  PARSED_KEY=""
  PARSED_SLUG=""
  if [[ "$url" == *://* ]]; then
    rest="${url#*://}"
    authority="${rest%%/*}"
    path="${rest#*/}"
    host="${authority##*@}"
    host="${host%%:*}"
  elif [[ "$url" =~ ^[^@]+@([^:]+):(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  else
    return 1
  fi
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  path="${path#/}"
  path="${path%/}"
  path="${path%.git}"
  [[ "$host" == "github.com" && "$path" =~ ^[^/]+/[^/]+$ ]] || return 1
  PARSED_SLUG="$path"
  PARSED_KEY="github.com/$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
}

lookup_override() {
  local key="$1" i configured entry name value
  OVERRIDE_VALUE=""
  for ((i = 0; i < ${#OVERRIDE_KEYS[@]}; i++)); do
    if [[ "${OVERRIDE_KEYS[$i]}" == "$key" ]]; then
      OVERRIDE_VALUE="${OVERRIDE_PATHS[$i]}"
      return 0
    fi
  done
  if [[ -n "$CONFIG_FILE" ]]; then
    configured="$(run_git_probe config --file "$CONFIG_FILE" --get "canonical.$key.path" 2>/dev/null || true)"
    if [[ -z "$configured" ]]; then
      # git config subsection names are case-sensitive, so a config section
      # written with GitHub's display casing (the setup skill allows
      # case-preserving owner/name) never matches the lowercase key above --
      # regardless of what casing the discovered remote itself happens to
      # use, which need not match the config's casing either. Scan every
      # canonical.*.path entry and compare case-insensitively.
      while IFS= read -r -d '' entry; do
        name="${entry%%$'\n'*}"
        value="${entry#*$'\n'}"
        name="${name#canonical.}"
        name="${name%.path}"
        if [[ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" == "$key" ]]; then
          configured="$value"
          break
        fi
      done < <(run_git_probe config --file "$CONFIG_FILE" --get-regexp -z \
        '^canonical\.[^[:cntrl:]]+\.path$' 2>/dev/null || true)
    fi
    if [[ -n "$configured" ]]; then
      OVERRIDE_VALUE="$(resolve_input_path "$configured" "$CONFIG_DIR")"
      return 0
    fi
  fi
  return 1
}

github_identity() {
  local slug="$1" result error
  GH_ID_STATUS="UNKNOWN"
  GH_ID_ACTUAL=""
  GH_ID_DEFAULT=""
  GH_ID_REASON="GitHub CLI unavailable or unauthenticated"
  $GH_READY || return 1
  if ! result="$(run_bounded_gh api "repos/$slug" --hostname github.com --method GET \
    --template '{{printf "%s\t%s" .full_name .default_branch}}' 2>&1)"; then
    if [[ "$result" == *"HTTP 404"* ]]; then
      error="HTTP 404 (not found or inaccessible)"
    elif [[ "$result" == *"HTTP 403"* ]]; then
      error="HTTP 403 (forbidden or inaccessible)"
    else
      error="GitHub API request failed"
    fi
    GH_ID_REASON="$error"
    return 1
  fi
  IFS=$'\t' read -r GH_ID_ACTUAL GH_ID_DEFAULT <<<"$result"
  [[ -n "$GH_ID_ACTUAL" ]] || {
    GH_ID_REASON="GitHub API returned no canonical repository identity"
    return 1
  }
  GH_ID_STATUS="OK"
  GH_ID_REASON=""
  return 0
}

FINDINGS_HIGH=0
FINDINGS_MEDIUM=0
FINDINGS_LOW=0
FINDINGS_UNKNOWN=0
REPOS_AUDITED=0

emit_finding() {
  local confidence="$1" kind="$2" target="$3" evidence="$4" disposition="$5" handoff="$6"
  case "$confidence" in
  HIGH) FINDINGS_HIGH=$((FINDINGS_HIGH + 1)) ;;
  MEDIUM) FINDINGS_MEDIUM=$((FINDINGS_MEDIUM + 1)) ;;
  LOW) FINDINGS_LOW=$((FINDINGS_LOW + 1)) ;;
  *) FINDINGS_UNKNOWN=$((FINDINGS_UNKNOWN + 1)) ;;
  esac
  print_field Finding "$kind"
  print_field Confidence "$confidence"
  print_field Target "$target"
  print_field Evidence "$evidence"
  print_field Disposition "$disposition"
  print_field Handoff "$handoff"
  printf '%s\n' '---'
}

analyze_repo() {
  local discovered="$1" discovered_remote="" discovered_url="" discovered_key="" discovered_slug=""
  local canonical="$discovered" canonical_remote="" canonical_url="" canonical_key="" canonical_slug=""
  local override_source="git-native" expected_actual="" expected_default="" expected_reason=""
  local canonical_actual="" canonical_reason="" github_repo="" default_branch="" current_branch=""
  local expected_common="" actual_common="" branch tip pr_match pr_any
  local pr_num pr_branch pr_oid pr_merged pr_url attached wt_index branch_index is_main ancestry_status
  local ref_record branch_status=1 branch_inventory_valid=true
  local remote_ref_record remote_branch_status=1 remote_branch_short remote_branch_known
  local repo_pr_rows="" exact_pr_rows="" repo_pr_available=false protected=false
  local -a WT_PATHS=() WT_BRANCHES=() WT_PRUNABLE=() WT_LOCKED=()
  local -a BRANCH_NAMES=() BRANCH_TIPS=() REMOTE_BRANCH_NAMES=()

  select_remote "$discovered" && {
    discovered_remote="$SELECTED_REMOTE"
    discovered_url="$SELECTED_URL"
    if parse_github_url "$discovered_url"; then
      discovered_key="$PARSED_KEY"
      discovered_slug="$PARSED_SLUG"
    fi
  }

  if [[ -n "$discovered_key" ]] && lookup_override "$discovered_key"; then
    [[ -d "$OVERRIDE_VALUE" ]] || {
      printf '\n'
      print_field Repo "$discovered"
      print_field Canonical unresolved
      emit_finding UNKNOWN canonical-override-invalid "$OVERRIDE_VALUE" \
        "override for $discovered_key is not a directory" "Stop for this repository" "Correct the override and rerun"
      return
    }
    canonical="$(run_git_probe -C "$OVERRIDE_VALUE" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || {
      printf '\n'
      print_field Repo "$discovered"
      print_field Canonical unresolved
      emit_finding UNKNOWN canonical-override-invalid "$OVERRIDE_VALUE" \
        "override for $discovered_key is not a Git working tree" "Stop for this repository" "Correct the override and rerun"
      return
    }
    override_source="configured"
  fi

  select_remote "$canonical" && {
    canonical_remote="$SELECTED_REMOTE"
    canonical_url="$SELECTED_URL"
    if parse_github_url "$canonical_url"; then
      canonical_key="$PARSED_KEY"
      canonical_slug="$PARSED_SLUG"
    fi
  }

  printf '\n'
  print_field Repo "$discovered"
  print_field Canonical "$canonical"
  print_field 'Canonical resolution' "$override_source"
  print_field Remote "${discovered_key:-unknown}"

  if [[ -z "$discovered_key" ]]; then
    emit_finding UNKNOWN github-identity-unavailable "$discovered" \
      "remote is missing, ambiguous, credential-only, or not a github.com owner/repository URL" \
      "Local Git/worktree evidence only" "Configure/select an unambiguous GitHub remote and rerun"
  else
    github_identity "$discovered_slug"
    expected_actual="$GH_ID_ACTUAL"
    expected_default="$GH_ID_DEFAULT"
    expected_reason="$GH_ID_REASON"
    if [[ "$GH_ID_STATUS" == "OK" ]]; then
      github_repo="$expected_actual"
      if [[ "$(lower "$expected_actual")" != "$(lower "$discovered_slug")" ]]; then
        emit_finding HIGH github-remote-moved "$discovered_remote ($discovered_slug -> $expected_actual)" \
          "GitHub REST resolved the configured remote identity to canonical full_name $expected_actual" \
          "Human-reviewed remote update" "Review git remote set-url for $discovered_remote in $discovered"
      fi
    else
      emit_finding UNKNOWN github-identity-unavailable "$discovered_key" "$expected_reason" \
        "Do not infer moved, deleted, or clean" "Restore GitHub access/authentication and rerun"
    fi
  fi

  if [[ "$canonical" != "$discovered" ]]; then
    if [[ -z "$canonical_key" ]]; then
      emit_finding UNKNOWN canonical-identity-unverified "$canonical" \
        "canonical override has a missing, ambiguous, credential-only, or non-github.com remote" \
        "Stop; do not combine canonical local state with discovered GitHub evidence" \
        "Correct the canonical override/remote and rerun"
      return
    fi
    if [[ "$(lower "$canonical_key")" != "$(lower "$discovered_key")" ]]; then
      github_identity "$canonical_slug"
      canonical_actual="$GH_ID_ACTUAL"
      canonical_reason="$GH_ID_REASON"
      if [[ -z "$expected_actual" || -z "$canonical_actual" ]]; then
        emit_finding UNKNOWN canonical-identity-unverified "$canonical" \
          "different remote identities could not both be verified: ${canonical_reason:-discovered identity unavailable}" \
          "Stop; do not combine local/GitHub evidence" "Restore GitHub access or correct the override"
        return
      fi
      if [[ "$(lower "$expected_actual")" != "$(lower "$canonical_actual")" ]]; then
        emit_finding UNKNOWN canonical-identity-conflict "$canonical" \
          "discovered checkout resolves to $expected_actual but override resolves to $canonical_actual" \
          "Stop; do not combine local/GitHub evidence" "Correct the canonical override and rerun"
        return
      fi
    fi
  fi

  expected_common="$(run_git_probe -C "$canonical" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
  [[ -n "$expected_common" ]] || {
    emit_finding UNKNOWN git-common-dir-unavailable "$canonical" "git could not resolve the canonical common directory" \
      "Stop for this repository" "Repair/replace the canonical override, then rerun"
    return
  }

  # Parse the stable NUL-delimited porcelain format. Only these registrations are worktree evidence.
  local wt_path="" wt_branch="" wt_prunable="false" wt_locked="false" field worktree_status=1
  while IFS= read -r -d '' field; do
    if [[ -z "$field" ]]; then
      if [[ -n "$wt_path" ]]; then
        WT_PATHS+=("$wt_path")
        WT_BRANCHES+=("$wt_branch")
        WT_PRUNABLE+=("$wt_prunable")
        WT_LOCKED+=("$wt_locked")
      fi
      wt_path="" wt_branch="" wt_prunable="false" wt_locked="false"
      continue
    fi
    case "$field" in
    __repo_fleet_status__\ *) worktree_status="${field#__repo_fleet_status__ }" ;;
    worktree\ *) wt_path="${field#worktree }" ;;
    branch\ refs/heads/*) wt_branch="${field#branch refs/heads/}" ;;
    prunable*) wt_prunable="true" ;;
    locked*) wt_locked="true" ;;
    *) ;;
    esac
  done < <(
    run_git_probe -C "$canonical" worktree list --porcelain -z -- 2>/dev/null
    printf '\0__repo_fleet_status__ %s\0' "$?"
  )
  if [[ "$worktree_status" != "0" ]]; then
    emit_finding UNKNOWN worktree-inventory-unavailable "$canonical" \
      "git worktree list --porcelain -z failed" \
      "Stop local branch/worktree classification for this repository" \
      "Repair Git metadata or correct the canonical checkout, then rerun"
    return
  fi
  if [[ -n "$wt_path" ]]; then
    WT_PATHS+=("$wt_path")
    WT_BRANCHES+=("$wt_branch")
    WT_PRUNABLE+=("$wt_prunable")
    WT_LOCKED+=("$wt_locked")
  fi

  for ((wt_index = 0; wt_index < ${#WT_PATHS[@]}; wt_index++)); do
    wt_path="${WT_PATHS[$wt_index]}"
    wt_branch="${WT_BRANCHES[$wt_index]}"
    is_main=false
    [[ "$wt_index" -eq 0 ]] && is_main=true
    if [[ "${WT_LOCKED[$wt_index]}" == "true" && "$is_main" == "false" ]]; then
      emit_finding HIGH locked-worktree "$wt_path${wt_branch:+ ($wt_branch)}" \
        "git worktree porcelain marks the registration locked" \
        "Manual review before any cleanup handoff" \
        "Inspect the lock reason with git worktree list --verbose in $canonical"
    fi
    if [[ ! -d "$wt_path" ]]; then
      if [[ "${WT_PRUNABLE[$wt_index]}" == "true" ]]; then
        emit_finding HIGH prunable-worktree "$wt_path${wt_branch:+ ($wt_branch)}" \
          "git worktree porcelain marks the missing registration prunable" \
          "Candidate dry-run handoff" "Run /source-control:worktree cleanup --dry-run in $canonical"
      else
        emit_finding MEDIUM missing-worktree "$wt_path${wt_branch:+ ($wt_branch)}" \
          "registered worktree path is absent but not currently marked prunable" \
          "Manual review" "Run /source-control:worktree cleanup --dry-run in $canonical"
      fi
      continue
    fi
    if ! actual_common="$(run_git_probe -C "$wt_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')" ||
      [[ -z "$actual_common" ]]; then
      emit_finding UNKNOWN worktree-common-dir-unavailable "$wt_path${wt_branch:+ ($wt_branch)}" \
        "git could not resolve the registered worktree common directory" \
        "Do not infer an administrative mismatch" \
        "Inspect the registered path and Git metadata, then rerun"
    elif [[ "$(path_key "$actual_common")" != "$(path_key "$expected_common")" ]]; then
      emit_finding HIGH worktree-admin-mismatch "$wt_path${wt_branch:+ ($wt_branch)}" \
        "expected common dir $expected_common; actual $actual_common" \
        "Manual administrative-directory decision; never auto-repair/remove" \
        "Inspect both repositories; consider git worktree repair only after choosing the authority"
    fi
  done

  default_branch="$expected_default"
  if [[ -z "$default_branch" && -n "$canonical_remote" ]]; then
    default_branch="$(run_git_probe -C "$canonical" symbolic-ref "refs/remotes/$canonical_remote/HEAD" 2>/dev/null | sed "s|^refs/remotes/$canonical_remote/||" | tr -d '\r')"
  fi
  if ! current_branch="$(run_git_probe -C "$canonical" branch --show-current 2>/dev/null | tr -d '\r')"; then
    emit_finding UNKNOWN current-branch-unavailable "$canonical" \
      "git branch --show-current failed" \
      "Stop local branch classification; the checked-out branch cannot be protected reliably" \
      "Repair Git metadata or correct the canonical checkout, then rerun"
    return
  fi

  # Git emits one LF after every custom for-each-ref format. Terminate each complete branch/tip
  # record with an explicit NUL, strip only that Git-added record separator, and preserve the
  # producer's exit status in a separate NUL field. Never classify partial output from a failed probe.
  while IFS= read -r -d '' ref_record; do
    while [[ "$ref_record" == $'\n'* || "$ref_record" == $'\r'* ]]; do
      ref_record="${ref_record:1}"
    done
    [[ -n "$ref_record" ]] || continue
    if [[ "$ref_record" == __repo_fleet_ref_status__\ * ]]; then
      branch_status="${ref_record#__repo_fleet_ref_status__ }"
      continue
    fi
    if [[ "$ref_record" != *$'\t'* ]]; then
      branch_inventory_valid=false
      continue
    fi
    branch="${ref_record%%$'\t'*}"
    tip="${ref_record#*$'\t'}"
    if [[ -z "$branch" || -z "$tip" || "$tip" == *$'\t'* ]]; then
      branch_inventory_valid=false
      continue
    fi
    BRANCH_NAMES+=("$branch")
    BRANCH_TIPS+=("$tip")
  done < <(
    run_git_probe -C "$canonical" for-each-ref \
      '--format=%(refname:short)%09%(objectname)%00' -- refs/heads/ 2>/dev/null
    printf '\0__repo_fleet_ref_status__ %s\0' "$?"
  )
  if [[ "$branch_status" != "0" || "$branch_inventory_valid" != "true" ]]; then
    emit_finding UNKNOWN branch-inventory-unavailable "$canonical" \
      "git for-each-ref failed or returned a malformed branch/tip record" \
      "Stop local branch classification for this repository" \
      "Repair Git metadata or correct the canonical checkout, then rerun"
    return
  fi

  # Every local branch name is a candidate for the exact per-branch GitHub query below, but only
  # a branch already represented on the remote may actually be sent there -- this repo's security
  # posture (security-review.md) promises GitHub sees only identifiers the remote already carries.
  # Enumerate remote-tracking branches purely locally (no network) so that promise holds even for
  # a branch that only ever existed on this machine.
  if [[ -n "$canonical_remote" ]]; then
    while IFS= read -r -d '' remote_ref_record; do
      while [[ "$remote_ref_record" == $'\n'* || "$remote_ref_record" == $'\r'* ]]; do
        remote_ref_record="${remote_ref_record:1}"
      done
      [[ -n "$remote_ref_record" ]] || continue
      if [[ "$remote_ref_record" == __repo_fleet_ref_status__\ * ]]; then
        remote_branch_status="${remote_ref_record#__repo_fleet_ref_status__ }"
        continue
      fi
      [[ "$remote_ref_record" == *$'\t'* ]] || continue
      remote_branch_short="${remote_ref_record%%$'\t'*}"
      # refs/remotes/<remote>/ also yields a bare "<remote>" entry (the symbolic HEAD pointer to
      # the remote's default branch, e.g. refs/remotes/origin/HEAD -> refname:short "origin") --
      # require the literal "<remote>/" prefix so that entry is excluded, not misread as a branch.
      if [[ "$remote_branch_short" == "$canonical_remote/"* ]]; then
        remote_branch_short="${remote_branch_short#"$canonical_remote"/}"
        [[ -n "$remote_branch_short" ]] && REMOTE_BRANCH_NAMES+=("$remote_branch_short")
      fi
    done < <(
      run_git_probe -C "$canonical" for-each-ref \
        '--format=%(refname:short)%09%(objectname)%00' -- "refs/remotes/$canonical_remote/" 2>/dev/null
      printf '\0__repo_fleet_ref_status__ %s\0' "$?"
    )
    if [[ "$remote_branch_status" != "0" ]]; then
      # The producer may have emitted and appended some records before failing partway through;
      # discard them so a partial remote-ref inventory can never make remote_branch_known true
      # below and drive the exact --head fallback query on stale/incomplete evidence.
      REMOTE_BRANCH_NAMES=()
      emit_finding UNKNOWN remote-branch-inventory-unavailable "$canonical" \
        "git for-each-ref for refs/remotes/$canonical_remote/ failed" \
        "Exact per-branch GitHub lookups are skipped for every branch in this repository" \
        "Repair Git metadata or correct the canonical checkout, then rerun"
    fi
  fi

  # One repository-scoped query avoids N network round trips while keeping same-named branches
  # isolated by --repo. A finite limit can cause a false negative, never a false merged claim.
  if [[ -n "$github_repo" && "$GH_READY" == "true" ]]; then
    repo_pr_rows="$(run_bounded_gh pr list --repo "github.com/$github_repo" --state merged --limit 200 \
      --json number,headRefName,headRefOid,mergedAt,url \
      --template '{{range .}}{{printf "%v\t%s\t%s\t%s\t%s\n" .number .headRefName .headRefOid .mergedAt .url}}{{end}}' 2>/dev/null)" &&
      repo_pr_available=true
    if [[ "$repo_pr_available" != "true" ]]; then
      emit_finding UNKNOWN github-pr-evidence-unavailable "$github_repo" \
        "repository-scoped merged-PR query failed" "Do not infer branch merge state" \
        "Restore GitHub access/authentication and rerun"
    fi
  fi

  for ((branch_index = 0; branch_index < ${#BRANCH_NAMES[@]}; branch_index++)); do
    branch="${BRANCH_NAMES[$branch_index]}"
    tip="${BRANCH_TIPS[$branch_index]}"
    attached=false
    is_main=false
    for ((wt_index = 0; wt_index < ${#WT_BRANCHES[@]}; wt_index++)); do
      if [[ "${WT_BRANCHES[$wt_index]}" == "$branch" ]]; then
        attached=true
        [[ "$wt_index" -eq 0 ]] && is_main=true
      fi
    done
    protected=false
    [[ "$branch" == "$default_branch" || "$branch" == "$current_branch" ]] && protected=true
    [[ "$is_main" == "true" ]] && protected=true

    pr_match="" pr_any=""
    if [[ "$repo_pr_available" == "true" && "$branch" != "$default_branch" ]]; then
      while IFS=$'\t' read -r pr_num pr_branch pr_oid pr_merged pr_url; do
        [[ -n "$pr_num" ]] || continue
        [[ "$pr_branch" == "$branch" ]] || continue
        [[ -z "$pr_any" ]] && pr_any="$pr_num|$pr_oid|$pr_merged|$pr_url"
        if [[ "$pr_oid" == "$tip" ]]; then
          pr_match="$pr_num|$pr_oid|$pr_merged|$pr_url"
          break
        fi
      done <<<"$repo_pr_rows"
      # The batch is an optimization, not an evidence boundary. An exact repository+head fallback
      # prevents an older local branch from becoming a false negative outside the recent-PR window.
      # Only send a branch name GitHub can already see: --head transmits it verbatim to github.com,
      # so a purely local branch (never pushed) must never reach this query at all.
      if [[ -z "$pr_match" ]]; then
        remote_branch_known=false
        for remote_branch_short in "${REMOTE_BRANCH_NAMES[@]}"; do
          [[ "$remote_branch_short" == "$branch" ]] && {
            remote_branch_known=true
            break
          }
        done
        if [[ "$remote_branch_known" == "true" ]]; then
          if exact_pr_rows="$(run_bounded_gh pr list --repo "github.com/$github_repo" --state merged --head "$branch" --limit 100 \
            --json number,headRefName,headRefOid,mergedAt,url \
            --template '{{range .}}{{printf "%v\t%s\t%s\t%s\t%s\n" .number .headRefName .headRefOid .mergedAt .url}}{{end}}' 2>/dev/null)"; then
            while IFS=$'\t' read -r pr_num pr_branch pr_oid pr_merged pr_url; do
              [[ -n "$pr_num" && "$pr_branch" == "$branch" ]] || continue
              [[ -z "$pr_any" ]] && pr_any="$pr_num|$pr_oid|$pr_merged|$pr_url"
              if [[ "$pr_oid" == "$tip" ]]; then
                pr_match="$pr_num|$pr_oid|$pr_merged|$pr_url"
                break
              fi
            done <<<"$exact_pr_rows"
          else
            emit_finding UNKNOWN github-pr-evidence-unavailable "$canonical :: $branch" \
              "exact repository-and-head merged-PR query failed" "Do not infer branch merge state" \
              "Restore GitHub access/authentication and rerun"
          fi
        fi
      fi
    fi

    if [[ -n "$pr_match" ]]; then
      IFS='|' read -r pr_num pr_oid pr_merged pr_url <<<"$pr_match"
      if [[ "$attached" == "true" && "$is_main" == "false" ]]; then
        emit_finding HIGH merged-worktree "$canonical :: $branch" \
          "GitHub PR #$pr_num MERGED; headRefOid $pr_oid equals local tip; branch is worktree-attached" \
          "Candidate worktree dry-run handoff before branch cleanup" \
          "Run /source-control:worktree cleanup --dry-run in $canonical"
      elif [[ "$protected" == "false" ]]; then
        emit_finding HIGH merged-local-branch "$canonical :: $branch" \
          "GitHub PR #$pr_num MERGED; headRefOid $pr_oid equals local tip ($pr_url)" \
          "Candidate per-repository branch-audit handoff" "Run /repo-hygiene:clean git in $canonical"
      fi
    elif [[ -n "$pr_any" && "$branch" != "$default_branch" ]]; then
      IFS='|' read -r pr_num pr_oid pr_merged pr_url <<<"$pr_any"
      emit_finding MEDIUM merged-pr-tip-drift "$canonical :: $branch" \
        "GitHub PR #$pr_num MERGED at headRefOid $pr_oid, but current local tip is $tip" \
        "Manual review; not a cleanup candidate" "Inspect commits added after PR #$pr_num"
    elif [[ "$protected" == "false" && "$attached" == "false" && -n "$canonical_remote" && -n "$default_branch" ]]; then
      run_git_probe -C "$canonical" merge-base --is-ancestor "$tip" \
        "refs/remotes/$canonical_remote/$default_branch" 2>/dev/null
      ancestry_status=$?
      if [[ "$ancestry_status" == "0" ]]; then
        emit_finding LOW local-ancestry-only "$canonical :: $branch" \
          "local tip is an ancestor of $canonical_remote/$default_branch; no matching GitHub merged-PR evidence" \
          "Informational only" "Review in /repo-hygiene:clean git; do not infer PR merge"
      elif [[ "$ancestry_status" != "1" ]]; then
        emit_finding UNKNOWN local-ancestry-unavailable "$canonical :: $branch" \
          "git merge-base --is-ancestor failed with status $ancestry_status" \
          "Do not infer local ancestry" "Repair Git metadata or restore missing objects, then rerun"
      fi
    fi
  done

  REPOS_AUDITED=$((REPOS_AUDITED + 1))
}

printf 'Repo Fleet Hygiene Audit\n'
printf 'Mode: read-only (no fetch, prune, repair, delete, checkout, or remote update)\n'
if [[ -n "$CONFIG_FILE" ]]; then
  print_field Config "$CONFIG_FILE ($CONFIG_SOURCE)"
else
  print_field Config "none (no explicit, project, or user-global config; current-project scope)"
fi
printf 'GitHub evidence: %s\n' "$([[ "$GH_READY" == "true" ]] && echo available || echo unavailable)"
printf 'Repositories discovered: %s\n' "${#TARGETS[@]}"

for target in "${TARGETS[@]}"; do
  analyze_repo "$target"
done

printf '\nSummary: repositories=%s high=%s medium=%s low=%s unknown=%s\n' \
  "$REPOS_AUDITED" "$FINDINGS_HIGH" "$FINDINGS_MEDIUM" "$FINDINGS_LOW" "$FINDINGS_UNKNOWN"
printf 'Mutation count: 0\n'
