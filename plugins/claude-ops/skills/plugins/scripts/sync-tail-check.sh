#!/usr/bin/env bash
# Read-only checks for the operator-gated plugin-sync tail (#4186).
#
# Nothing here writes settings, deletes a cache tree, or edits another
# repository. A missing permission rule is printed as a seed the operator
# adds. A removed marketplace's cache is reported against both documented
# sweep windows. Adjacent drift is classified from fetched text or left
# unprobed when the read fails.
#
#   sync-tail-check.sh --check-permissions [--settings <file>]
#   sync-tail-check.sh --check-orphan [--cache <dir>] [--known <file>] [--marketplace <name>]
#   sync-tail-check.sh --check-drift [--fixture <dir> | --offline]
#
# Exit: 0 nothing actionable, 1 a finding the operator can act on, 2 usage
# or a missing tool, 3 a check input that cannot be read.
set -uo pipefail

usage() {
  cat <<'EOF'
sync-tail-check.sh — read-only checks for the operator-gated plugin-sync tail.

Usage:
  sync-tail-check.sh --check-permissions [--settings <file>]
  sync-tail-check.sh --check-orphan [--cache <dir>] [--known <file>] [--marketplace <name>]
  sync-tail-check.sh --check-drift [--fixture <dir> | --offline]

Exit: 0 nothing actionable; 1 a finding; 2 usage or a missing tool;
3 an input that cannot be read. The script never writes the settings file,
never deletes a cache tree, and never edits another repository.
EOF
}

MODE=""
SETTINGS=""
CACHE=""
KNOWN=""
MARKET=""
FIXTURE=""
OFFLINE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --check-permissions)
    MODE="permissions"
    shift
    ;;
  --check-orphan)
    MODE="orphan"
    shift
    ;;
  --check-drift)
    MODE="drift"
    shift
    ;;
  --settings)
    SETTINGS="${2:-}"
    shift 2
    ;;
  --cache)
    CACHE="${2:-}"
    shift 2
    ;;
  --known)
    KNOWN="${2:-}"
    shift 2
    ;;
  --marketplace)
    MARKET="${2:-}"
    shift 2
    ;;
  --fixture)
    FIXTURE="${2:-}"
    shift 2
    ;;
  --offline)
    OFFLINE=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "ERROR: one of --check-permissions, --check-orphan, --check-drift is required" >&2
  usage >&2
  exit 2
fi

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required" >&2
    exit 2
  fi
}

check_permissions() {
  need_jq
  local file="${SETTINGS:-${HOME}/.claude/settings.json}"
  local rule='Bash(gh pr merge *)'
  echo "rule: $rule"
  echo "settings: $file"
  if [[ ! -e "$file" ]]; then
    echo "status: absent"
    echo "seed: {\"permissions\":{\"allow\":[\"Bash(gh pr merge *)\"]}}"
    echo "note: file missing; this check does not create it"
    exit 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "ERROR: settings path is not a file: $file" >&2
    exit 3
  fi
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "ERROR: settings file is not JSON: $file" >&2
    exit 3
  fi
  local exact broader
  # `--auto` grants do not satisfy the plain merge rule. The colon form is
  # the same grant as the space form this issue names.
  exact="$(jq -r '[(.permissions.allow // [])[] | select(. == "Bash(gh pr merge *)" or . == "Bash(gh pr merge:*)")] | length' "$file")"
  broader="$(jq -r '[(.permissions.allow // [])[] | select(type == "string" and contains("gh pr merge") and (contains("--auto") | not) and . != "Bash(gh pr merge *)" and . != "Bash(gh pr merge:*)")] | length' "$file")"
  if [[ "$exact" -ge 1 ]]; then
    echo "status: present-exact"
    exit 0
  fi
  if [[ "$broader" -ge 1 ]]; then
    echo "status: present-broader"
    echo "note: an allow entry mentions gh pr merge and is not the exact rule"
    exit 0
  fi
  echo "status: absent"
  echo "seed: {\"permissions\":{\"allow\":[\"Bash(gh pr merge *)\"]}}"
  echo "note: add the seed beside the other gh pr rules; this check does not write the file"
  exit 1
}

sweep_word() {
  local age="$1"
  if [[ "$age" -lt 7 ]]; then
    printf 'pending'
  elif [[ "$age" -lt 14 ]]; then
    printf 'split'
  else
    printf 'overdue'
  fi
}

check_orphan() {
  local cache="${CACHE:-${HOME}/.claude/plugins/cache}"
  local known="${KNOWN:-${HOME}/.claude/plugins/known_marketplaces.json}"
  echo "cache: $cache"
  echo "known: $known"
  echo "windows: plugins-reference=14d claude-directory=7d fetched=2026-09-28"
  if [[ ! -d "$cache" ]]; then
    if [[ -n "$MARKET" ]]; then
      echo "removed-marketplace $MARKET tree=absent reason=unobserved"
      echo "status: clean"
      exit 0
    fi
    echo "ERROR: cache directory not found: $cache" >&2
    exit 3
  fi
  if [[ ! -f "$known" ]]; then
    echo "ERROR: known_marketplaces.json not found: $known" >&2
    exit 3
  fi
  need_jq
  if ! jq -e 'type == "object"' "$known" >/dev/null 2>&1; then
    echo "ERROR: known marketplaces file is not a JSON object" >&2
    exit 3
  fi
  local actionable=0
  local name dir marker_file marker now sec age word
  now="$(date +%s)"
  if [[ -n "$MARKET" && ! -d "$cache/$MARKET" ]]; then
    echo "removed-marketplace $MARKET tree=absent reason=unobserved"
  fi
  for dir in "$cache"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    if jq -e --arg n "$name" 'has($n)' "$known" >/dev/null 2>&1; then
      continue
    fi
    if [[ -n "$MARKET" && "$name" != "$MARKET" ]]; then
      continue
    fi
    marker_file="$(find "$dir" -name '.orphaned_at' -type f | head -n 1)"
    if [[ -z "$marker_file" ]]; then
      echo "removed-marketplace $name tree=present marker=missing sweep=unmarked"
      actionable=1
      continue
    fi
    marker="$(tr -d '[:space:]' <"$marker_file")"
    if [[ ! "$marker" =~ ^[0-9]+$ ]]; then
      echo "removed-marketplace $name tree=present marker=unreadable sweep=unmarked"
      actionable=1
      continue
    fi
    sec=$((marker / 1000))
    if [[ "$sec" -gt "$now" ]]; then
      age=0
    else
      age=$(((now - sec) / 86400))
    fi
    word="$(sweep_word "$age")"
    echo "removed-marketplace $name tree=present marker=$marker age_days=$age sweep=$word"
    if [[ "$word" == "overdue" ]]; then
      actionable=1
    fi
  done
  if [[ "$actionable" -eq 1 ]]; then
    echo "status: actionable"
    exit 1
  fi
  echo "status: clean"
  exit 0
}

emit_item() {
  printf '%s status=%s note=%s\n' "$1" "$2" "$3"
  if [[ "$2" == "open" || "$2" == "waiting-on-release" ]]; then
    DRIFT_OPEN=1
  fi
}

classify_drift() {
  local dir="$1"
  DRIFT_OPEN=0
  if [[ -f "$dir/targets.fail" ]]; then
    emit_item a unprobed "standards claude-settings targets could not be read"
  elif [[ -f "$dir/targets.txt" ]] && grep -q 'account-rotation' "$dir/targets.txt"; then
    emit_item a clear "account-rotation target is present"
  elif [[ -f "$dir/targets.txt" ]]; then
    emit_item a open "no account-rotation target beside the listed claude-settings targets"
  else
    emit_item a unprobed "no targets listing"
  fi

  if [[ -f "$dir/release.fail" ]]; then
    emit_item b unprobed "ci-workflows release.yml could not be read"
    emit_item f unprobed "ci-workflows release.yml could not be read"
  elif [[ -f "$dir/release.yml" ]]; then
    local missing=0 path base
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      base="$(basename "$path")"
      if [[ -f "$dir/cited/${base}.missing" ]]; then
        missing=1
        emit_item b open "release.yml cites $path and that file is absent"
      fi
    done < <(grep -oE '\.github/workflows/[A-Za-z0-9_.-]+\.yml' "$dir/release.yml" | sort -u)
    if [[ "$missing" -eq 0 ]]; then
      emit_item b clear "every workflow path cited by release.yml was present"
    fi
    if grep -q 'latest existing tag' "$dir/release.yml"; then
      emit_item f open "release header still says the version comes from the latest existing tag"
    elif grep -q 'PUBLISHED' "$dir/release.yml"; then
      emit_item f clear "release header keys the version on published releases"
    else
      emit_item f unprobed "release header matched neither the old nor the published-release wording"
    fi
  else
    emit_item b unprobed "no release.yml"
    emit_item f unprobed "no release.yml"
  fi

  if [[ -f "$dir/readme.fail" || -f "$dir/latest.fail" ]]; then
    emit_item c unprobed "readme version or latest release could not be read"
  elif [[ -f "$dir/readme.txt" && -f "$dir/latest.txt" ]]; then
    local stated latest
    stated="$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$dir/readme.txt" | head -n 1)"
    latest="$(tr -d '[:space:]' <"$dir/latest.txt")"
    if [[ -n "$stated" && "$stated" == "$latest" ]]; then
      emit_item c clear "readme version $stated matches the latest release"
    elif [[ -n "$stated" ]]; then
      emit_item c open "readme says $stated and the latest release is $latest"
    else
      emit_item c unprobed "readme snippet had no version"
    fi
  else
    emit_item c unprobed "no readme version inputs"
  fi

  if [[ -f "$dir/acceptance.fail" ]]; then
    emit_item d unprobed "managed-files-guard README could not be read"
  elif [[ -f "$dir/acceptance.md" ]]; then
    if grep -q 'dependabot\[bot\]' "$dir/acceptance.md"; then
      emit_item d clear "acceptance bullet names dependabot[bot]"
    else
      emit_item d open "acceptance bullet does not name dependabot[bot]"
    fi
  else
    emit_item d unprobed "no acceptance excerpt"
  fi

  if [[ -f "$dir/github-iac.fail" ]]; then
    emit_item e unprobed "github-iac dependabot.yml is not readable from this token"
  elif [[ -f "$dir/github-iac.yml" ]]; then
    if grep -q 'melodic-software/ci-workflows/\*' "$dir/github-iac.yml"; then
      emit_item e clear "dependabot ignore includes melodic-software/ci-workflows/*"
    else
      emit_item e open "dependabot ignore does not widen to melodic-software/ci-workflows/*"
    fi
  else
    emit_item e unprobed "no github-iac dependabot input"
  fi

  emit_item g unprobed "upstream claude-community SessionEnd hook; disable it or file it there. This check does not edit that marketplace"

  if [[ -f "$dir/guard.fail" ]]; then
    emit_item h unprobed "managed-files-guard workflow could not be read"
  elif [[ -f "$dir/guard.yml" ]]; then
    if grep -q 'actions/checkout' "$dir/guard.yml"; then
      emit_item h waiting-on-release "standards component still checks out; moving checkout into the composite action waits on a ci-workflows release"
    else
      emit_item h clear "standards component no longer carries actions/checkout"
    fi
  else
    emit_item h unprobed "no managed-files-guard workflow"
  fi

  if [[ "$DRIFT_OPEN" -eq 1 ]]; then
    echo "status: actionable"
    exit 1
  fi
  echo "status: clean"
  exit 0
}

print_offline() {
  cat <<'EOF'
a status=unprobed note=gh api repos/melodic-software/standards/contents/components/claude-settings/targets
b status=unprobed note=gh api repos/melodic-software/ci-workflows/contents/.github/workflows/release.yml then confirm each cited workflow path
c status=unprobed note=compare the README version sentence with gh release view --repo melodic-software/ci-workflows
d status=unprobed note=standards components/managed-files-guard/README.md acceptance bullet names dependabot[bot]
e status=unprobed note=github-iac .github/dependabot.yml ignore widened to melodic-software/ci-workflows/*
f status=unprobed note=ci-workflows release.yml header keys the version on published releases
g status=unprobed note=upstream claude-community SessionEnd hook; disable it or file it there
h status=unprobed note=standards managed-files-guard still carries actions/checkout until a ci-workflows release absorbs it
status: offline
EOF
  exit 0
}

fetch_live() {
  local dir="$1"
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh is required for a live drift check; pass --offline or --fixture" >&2
    exit 2
  fi
  mkdir -p "$dir/cited"
  if gh api repos/melodic-software/standards/contents/components/claude-settings/targets --jq '.[].name' >"$dir/targets.txt" 2>"$dir/targets.err"; then
    rm -f "$dir/targets.err"
  else
    : >"$dir/targets.fail"
  fi
  if gh api -H "Accept: application/vnd.github.raw" /repos/melodic-software/ci-workflows/contents/.github/workflows/release.yml >"$dir/release.yml" 2>"$dir/release.err"; then
    local path base
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      base="$(basename "$path")"
      if ! gh api "repos/melodic-software/ci-workflows/contents/${path}" --jq .name >/dev/null 2>&1; then
        : >"$dir/cited/${base}.missing"
      fi
    done < <(grep -oE '\.github/workflows/[A-Za-z0-9_.-]+\.yml' "$dir/release.yml" | sort -u)
  else
    : >"$dir/release.fail"
  fi
  if gh api -H "Accept: application/vnd.github.raw" /repos/melodic-software/ci-workflows/contents/README.md >"$dir/readme.full" 2>"$dir/readme.err"; then
    grep -n 'This repository is' "$dir/readme.full" | head -n 1 >"$dir/readme.txt" || : >"$dir/readme.txt"
  else
    : >"$dir/readme.fail"
  fi
  if gh api repos/melodic-software/ci-workflows/releases/latest --jq .tag_name >"$dir/latest.txt" 2>"$dir/latest.err"; then
    :
  else
    : >"$dir/latest.fail"
  fi
  if gh api -H "Accept: application/vnd.github.raw" /repos/melodic-software/standards/contents/components/managed-files-guard/README.md >"$dir/acceptance.full" 2>"$dir/acceptance.err"; then
    awk 'BEGIN{p=0} /^## Ownership/{p=1} p{print} /^## Verification/{exit}' "$dir/acceptance.full" >"$dir/acceptance.md"
  else
    : >"$dir/acceptance.fail"
  fi
  if gh api -H "Accept: application/vnd.github.raw" /repos/melodic-software/github-iac/contents/.github/dependabot.yml >"$dir/github-iac.yml" 2>"$dir/github-iac.err"; then
    :
  else
    : >"$dir/github-iac.fail"
  fi
  if gh api -H "Accept: application/vnd.github.raw" /repos/melodic-software/standards/contents/components/managed-files-guard/managed-files-guard.yml >"$dir/guard.yml" 2>"$dir/guard.err"; then
    :
  else
    : >"$dir/guard.fail"
  fi
}

check_drift() {
  if [[ "$OFFLINE" -eq 1 ]]; then
    print_offline
  fi
  if [[ -n "$FIXTURE" ]]; then
    if [[ ! -d "$FIXTURE" ]]; then
      echo "ERROR: fixture directory not found: $FIXTURE" >&2
      exit 3
    fi
    classify_drift "$FIXTURE"
  fi
  local live
  live="$(mktemp -d)"
  fetch_live "$live"
  classify_drift "$live"
}

case "$MODE" in
permissions) check_permissions ;;
orphan) check_orphan ;;
drift) check_drift ;;
*)
  echo "ERROR: unknown mode" >&2
  exit 2
  ;;
esac
