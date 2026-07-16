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

# GitHub CLI exposes no request-timeout flag or documented timeout environment variable. Bound every
# outbound invocation with the platform's coreutils timeout command so one unreachable API cannot
# stall an entire fleet. GitHub evidence degrades to unavailable when neither spelling exists.
GH_TIMEOUT_COMMAND=""
if command -v timeout >/dev/null 2>&1; then
  GH_TIMEOUT_COMMAND="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  GH_TIMEOUT_COMMAND="gtimeout"
fi

run_bounded_gh() {
  [[ -n "$GH_TIMEOUT_COMMAND" ]] || return 125
  GH_PROMPT_DISABLED=1 GH_TELEMETRY=false GH_NO_UPDATE_NOTIFIER=1 \
    "$GH_TIMEOUT_COMMAND" 30 gh "$@"
}

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

if [[ -n "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" ]] || fail "config file not found: $CONFIG_FILE"
  CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" 2>/dev/null && pwd -P)/$(basename "$CONFIG_FILE")"
  git config --file "$CONFIG_FILE" --list >/dev/null 2>&1 || fail "invalid Git config: $CONFIG_FILE"
  CONFIG_DIR="$(dirname "$CONFIG_FILE")"
else
  CONFIG_DIR=""
fi

if [[ -z "$MAX_DEPTH" && -n "$CONFIG_FILE" ]]; then
  MAX_DEPTH="$(git config --file "$CONFIG_FILE" --get fleet.maxDepth 2>/dev/null || true)"
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
  done < <(git config --file "$CONFIG_FILE" --null --get-all fleet.root 2>/dev/null || true)
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] && REPO_ARGS+=("$(resolve_input_path "$value" "$CONFIG_DIR")")
  done < <(git config --file "$CONFIG_FILE" --null --get-all fleet.repo 2>/dev/null || true)
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
  top="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" ||
    fail "not a Git working tree: $candidate"
  common="$(git -C "$candidate" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')" ||
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
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    SELECTED_REMOTE="origin"
  else
    remotes="$(git -C "$repo" remote 2>/dev/null | tr -d '\r')"
    count="$(printf '%s\n' "$remotes" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$count" == "1" ]]; then
      SELECTED_REMOTE="$(printf '%s\n' "$remotes" | sed '/^$/d')"
    else
      SELECTED_REMOTE=""
      return 1
    fi
  fi
  SELECTED_URL="$(git -C "$repo" remote get-url "$SELECTED_REMOTE" 2>/dev/null | tr -d '\r')" || return 1
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
  local key="$1" i configured
  OVERRIDE_VALUE=""
  for ((i = 0; i < ${#OVERRIDE_KEYS[@]}; i++)); do
    if [[ "${OVERRIDE_KEYS[$i]}" == "$key" ]]; then
      OVERRIDE_VALUE="${OVERRIDE_PATHS[$i]}"
      return 0
    fi
  done
  if [[ -n "$CONFIG_FILE" ]]; then
    configured="$(git config --file "$CONFIG_FILE" --get "canonical.$key.path" 2>/dev/null || true)"
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
  if ! result="$(run_bounded_gh api "repos/$slug" --hostname github.com \
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
  local pr_num pr_branch pr_oid pr_merged pr_url attached wt_index is_main
  local repo_pr_rows="" exact_pr_rows="" repo_pr_available=false protected=false
  local -a WT_PATHS=() WT_BRANCHES=() WT_PRUNABLE=() WT_LOCKED=()

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
    canonical="$(git -C "$OVERRIDE_VALUE" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || {
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

  expected_common="$(git -C "$canonical" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
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
    git -C "$canonical" worktree list --porcelain -z 2>/dev/null
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
    actual_common="$(git -C "$wt_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
    if [[ -z "$actual_common" || "$(path_key "$actual_common")" != "$(path_key "$expected_common")" ]]; then
      emit_finding HIGH worktree-admin-mismatch "$wt_path${wt_branch:+ ($wt_branch)}" \
        "expected common dir $expected_common; actual ${actual_common:-unresolvable}" \
        "Manual administrative-directory decision; never auto-repair/remove" \
        "Inspect both repositories; consider git worktree repair only after choosing the authority"
    fi
  done

  default_branch="$expected_default"
  if [[ -z "$default_branch" && -n "$canonical_remote" ]]; then
    default_branch="$(git -C "$canonical" symbolic-ref "refs/remotes/$canonical_remote/HEAD" 2>/dev/null | sed "s|^refs/remotes/$canonical_remote/||" | tr -d '\r')"
  fi
  current_branch="$(git -C "$canonical" branch --show-current 2>/dev/null | tr -d '\r')"

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

  while IFS=$'\t' read -r branch tip; do
    [[ -n "$branch" ]] || continue
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
      if [[ -z "$pr_match" ]]; then
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
    elif [[ "$protected" == "false" && "$attached" == "false" && -n "$canonical_remote" && -n "$default_branch" ]] &&
      git -C "$canonical" merge-base --is-ancestor "$tip" "refs/remotes/$canonical_remote/$default_branch" 2>/dev/null; then
      emit_finding LOW local-ancestry-only "$canonical :: $branch" \
        "local tip is an ancestor of $canonical_remote/$default_branch; no matching GitHub merged-PR evidence" \
        "Informational only" "Review in /repo-hygiene:clean git; do not infer PR merge"
    fi
  done < <(git -C "$canonical" for-each-ref refs/heads/ --format='%(refname:short)%09%(objectname)' 2>/dev/null | tr -d '\r')

  REPOS_AUDITED=$((REPOS_AUDITED + 1))
}

printf 'Repo Fleet Hygiene Audit\n'
printf 'Mode: read-only (no fetch, prune, repair, delete, checkout, or remote update)\n'
printf 'GitHub evidence: %s\n' "$([[ "$GH_READY" == "true" ]] && echo available || echo unavailable)"
printf 'Repositories discovered: %s\n' "${#TARGETS[@]}"

for target in "${TARGETS[@]}"; do
  analyze_repo "$target"
done

printf '\nSummary: repositories=%s high=%s medium=%s low=%s unknown=%s\n' \
  "$REPOS_AUDITED" "$FINDINGS_HIGH" "$FINDINGS_MEDIUM" "$FINDINGS_LOW" "$FINDINGS_UNKNOWN"
printf 'Mutation count: 0\n'
