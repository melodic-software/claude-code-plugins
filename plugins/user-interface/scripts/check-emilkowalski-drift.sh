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
#   1  drift: a pinned file changed or is gone, or a new file appeared at the root or under skills/
#   2  unverifiable (git missing, network) or usage
#
# Tests source this file and replace fetch_tree.

set -uo pipefail

UPSTREAM_REPO="emilkowalski/skills"
UPSTREAM_BRANCH="main"
PIN="c8a79627b59d72d764d6ab6f2c87c09a48169833"
# upstream path|pinned blob SHA, for every file a row in the record takes from
PINNED=(
  "LICENSE|57b46f1fd11dc62351ea548104a88aa3f659c11b"
  "performance-cheatsheet.md|15f73d24a3b0e8a44d96d16d996719565b3ab7d5"
  "ui-cheatsheet.md|a5c803280b82f72dd11ed2136caaf0ea8c139a5c"
  "skills/animate/RECIPES.md|6744891261bdf0bb0473d77f2cc706f2d78b574e"
  "skills/animate/SKILL.md|2d3b63acc5e2afcbf54b5ba59792e69fa51bcb0d"
  "skills/animation-performance/SKILL.md|74c421e4e673cab84490f8b17b89735c30b0f555"
  "skills/animation-vocabulary/SKILL.md|5ab2976514c74a194ebf069506d95ff3a5a0084f"
  "skills/apple-design/SKILL.md|adf68c517f2d7d2781587d619de07f4de286da57"
  "skills/break-ui/CATALOG.md|46962bb89445b8526ea94994a79b49508573b5fd"
  "skills/break-ui/SKILL.md|091a28d488662d2451131f1aaa60a6dcd2391932"
  "skills/choreograph/RECIPES.md|17936a9cfc3e26224c5b4555f5a239758718815c"
  "skills/choreograph/SKILL.md|9fef0048d260be7bc05a909a03b52627bb3ccf37"
  "skills/emil-design-eng/SKILL.md|dc063c2a861922c1c9f2412b824b0862746304f5"
  "skills/find-animation-opportunities/SKILL.md|d3b030fbca9abad9220a032f72d425c6b7fa2de8"
  "skills/improve-animations/AUDIT.md|0862c446eea250326cdd2054fc3492c6707f4cf7"
  "skills/improve-animations/PLAN-TEMPLATE.md|239026b91f8032df191dde2085fd796b8c116d91"
  "skills/improve-animations/SKILL.md|d6e77f37272329af0cc36f9eeedbe5226e86ce63"
  "skills/mobile-native/SKILL.md|94bba21fcb990b850e06effbf5709c96a07446ad"
  "skills/pick-ui-library/SKILL.md|5e0028e988b88d2a88a019fdc978b4732243e467"
  "skills/prototype/PICKER.md|aaa88c0eba38eb01c00d4eb2b144e39f808fc26a"
  "skills/prototype/SKILL.md|dbcc1a23c66933f7372c0aacbce2b0d7cc6100b6"
  "skills/remove-animations/SKILL.md|100b7b7666f7d09c69a75ebb793e30e607058e77"
  "skills/review-animations/SKILL.md|591397b5308266f76671dacc3e44830a3e3e535f"
  "skills/review-animations/STANDARDS.md|67b6edb5ed45aeafe7e3706bb76e27f3bd209a92"
)
# Files present at the pin that the record omits; a change to them is not drift,
# but a root or skills/ path in neither list is a new upstream file.
KNOWN_OMITTED=(
  ".gitattributes"
  ".gitignore"
  ".pl"
  "README.md"
  "skills/animate-expo/RECIPES.md"
  "skills/animate-expo/SKILL.md"
  "skills/ask-sonner/API.md"
  "skills/ask-sonner/SKILL.md"
  "skills/write-swift/SKILL.md"
)

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }

# Turn `git ls-tree -r` output on stdin into "<blob sha> <path>" lines. Fields split on the tab,
# so a path containing spaces stays whole.
parse_tree() {
  awk -F"\t" '{ split($1, meta, " "); print meta[3], $2 }'
}

# Print "<blob sha> <path>" for every file on the upstream default branch;
# return 1 when the tree cannot be read.
fetch_tree() {
  local dir rc
  dir="$(mktemp -d)" || return 1
  if git clone --quiet --depth 1 --filter=blob:none --no-checkout --branch "$UPSTREAM_BRANCH" \
    "https://github.com/${UPSTREAM_REPO}.git" "$dir/repo" >/dev/null 2>&1; then
    git -C "$dir/repo" ls-tree -r HEAD | parse_tree
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
    current="$(awk -v p="$path" 'substr($0, index($0, " ") + 1) == p { print $1; exit }' <<<"$tree")"
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

  section "New upstream files"
  known="$(printf '%s\n' "${PINNED[@]%%|*}" "${KNOWN_OMITTED[@]}")"
  while read -r _ path; do
    [[ "$path" == skills/* || "$path" != */* ]] || continue
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
           at the root or under skills/. Exit 0 no drift, 1 drift, 2 unverifiable.
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
