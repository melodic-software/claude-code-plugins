#!/usr/bin/env bash
# Drift check for the emilkowalski/skills files this marketplace absorbed.
# Run weekly by .github/workflows/maintenance-check-upstream-drift.yml;
# docs/upstream/emilkowalski-skills.md is the attribution and pin record.
#
# Read-only. Reads the upstream default branch's tree once, through a blobless
# shallow clone into a temporary directory, then compares the blob SHA of each
# pinned file with its pin and reports any skill file the pin does not know.
#
# Usage: check-emilkowalski-drift.sh [--check | --help]
#
# Exit codes:
#   0  no drift
#   1  drift: a pinned file changed or is gone, or a new file appeared under skills/
#   2  unverifiable (git missing, network) or usage
#
# Tests source this file and replace fetch_tree.

set -uo pipefail

UPSTREAM_REPO="emilkowalski/skills"
UPSTREAM_BRANCH="main"
PIN="2d228630ba1446365f614a108cb8252f1feda202"
# upstream path|pinned blob SHA, for every file a row in the record takes from
PINNED=(
  "LICENSE|57b46f1fd11dc62351ea548104a88aa3f659c11b"
  "performance-cheatsheet.md|5b279577685cebabbfbb0197bd6b3a74591b3392"
  "skills/animate/RECIPES.md|6744891261bdf0bb0473d77f2cc706f2d78b574e"
  "skills/animate/SKILL.md|7c3b20c6ed681b2d47c9ca9e3ee0e659ed47d032"
  "skills/animation-performance/SKILL.md|d688dd7c3ba143c6ae17efd2bc665380d5252c5a"
  "skills/animation-vocabulary/SKILL.md|5ab2976514c74a194ebf069506d95ff3a5a0084f"
  "skills/apple-design/SKILL.md|adf68c517f2d7d2781587d619de07f4de286da57"
  "skills/break-ui/CATALOG.md|46962bb89445b8526ea94994a79b49508573b5fd"
  "skills/break-ui/SKILL.md|091a28d488662d2451131f1aaa60a6dcd2391932"
  "skills/emil-design-eng/SKILL.md|62ce902af8dd32c590ea7203e9ab2edb1d6ef81a"
  "skills/find-animation-opportunities/SKILL.md|d3b030fbca9abad9220a032f72d425c6b7fa2de8"
  "skills/improve-animations/AUDIT.md|94056154e532d695b8792ea67d701625b4f43b6e"
  "skills/improve-animations/PLAN-TEMPLATE.md|239026b91f8032df191dde2085fd796b8c116d91"
  "skills/improve-animations/SKILL.md|d6e77f37272329af0cc36f9eeedbe5226e86ce63"
  "skills/mobile-native/SKILL.md|94bba21fcb990b850e06effbf5709c96a07446ad"
  "skills/pick-ui-library/SKILL.md|5e0028e988b88d2a88a019fdc978b4732243e467"
  "skills/prototype/PICKER.md|aaa88c0eba38eb01c00d4eb2b144e39f808fc26a"
  "skills/prototype/SKILL.md|dbcc1a23c66933f7372c0aacbce2b0d7cc6100b6"
  "skills/review-animations/SKILL.md|577a64397267ce20960de2202950594d5bd6f9b6"
  "skills/review-animations/STANDARDS.md|863ea12ea94c1f7a47b5f7e1019e976aa82bd4cd"
)
# Skill files present at the pin that the record omits; a change to them is not
# drift, but a path under skills/ that is in neither list is a new upstream file.
KNOWN_OMITTED=(
  "skills/animate-expo/RECIPES.md"
  "skills/animate-expo/SKILL.md"
  "skills/ask-sonner/API.md"
  "skills/ask-sonner/SKILL.md"
  "skills/write-swift/SKILL.md"
)

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }

# Print "<blob sha> <path>" for every file on the upstream default branch;
# return 1 when the tree cannot be read.
fetch_tree() {
  local dir rc
  dir="$(mktemp -d)" || return 1
  if git clone --quiet --depth 1 --filter=blob:none --no-checkout --branch "$UPSTREAM_BRANCH" \
    "https://github.com/${UPSTREAM_REPO}.git" "$dir/repo" >/dev/null 2>&1; then
    git -C "$dir/repo" ls-tree -r HEAD | awk '{ print $3, $4 }'
    rc=$?
  else
    rc=1
  fi
  rm -rf "$dir"
  return "$rc"
}

run_check() {
  local tree entry path pinned current drift=0 known

  if ! tree="$(fetch_tree)" || [[ -z "$tree" ]]; then
    err "could not read the upstream tree of ${UPSTREAM_REPO}@${UPSTREAM_BRANCH} (network or git failure)"
    section "Summary"
    log "Unverifiable: the upstream tree could not be read."
    return 2
  fi

  section "Upstream ${UPSTREAM_REPO}@${UPSTREAM_BRANCH} vs pin ${PIN:0:12}"
  for entry in "${PINNED[@]}"; do
    IFS='|' read -r path pinned <<<"$entry"
    current="$(awk -v p="$path" '$2 == p { print $1; exit }' <<<"$tree")"
    if [[ -z "$current" ]]; then
      log "GONE       ${path}  (deleted or renamed upstream)"
      drift=1
    elif [[ "$current" == "$pinned" ]]; then
      log "unchanged  ${path}"
    else
      log "CHANGED    ${path}  ${pinned} -> ${current}"
      drift=1
    fi
  done

  section "New upstream skill files"
  known="$(printf '%s\n' "${PINNED[@]%%|*}" "${KNOWN_OMITTED[@]}")"
  while read -r _ path; do
    [[ "$path" == skills/* ]] || continue
    grep -qxF -- "$path" <<<"$known" && continue
    log "NEW        ${path}"
    drift=1
  done <<<"$tree"

  section "Summary"
  if ((drift)); then
    log "Drift detected. Compare: https://github.com/${UPSTREAM_REPO}/compare/${PIN}...${UPSTREAM_BRANCH}"
    log "Re-audit and re-pin per docs/upstream/emilkowalski-skills.md."
    return 1
  fi
  log "No drift. Upstream matches pin ${PIN:0:12}."
  return 0
}

print_help() {
  cat <<'EOF'
Usage: check-emilkowalski-drift.sh [--check | --help]

  --check  (default) Read-only: read the upstream tree once, compare the blob SHA of
           each pinned emilkowalski/skills file with its pin, and report new files
           under skills/. Exit 0 no drift, 1 drift, 2 unverifiable.
  --help   Show this message.
EOF
}

main() {
  case "${1:---check}" in
    -h | --help)
      print_help
      return 0
      ;;
    --check) ;;
    *)
      err "unknown mode: $1 (expected --check or --help)"
      return 2
      ;;
  esac
  command -v git >/dev/null 2>&1 || {
    err "git not on PATH"
    return 2
  }
  run_check
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
