#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token

UPSTREAM=melodic-software/ci-workflows
# The standards sync owns this file's pin.
MANAGED=.github/workflows/pr-check-managed-files-hosted.yml
FORMAL_MODELS='.claude/skills/formal-*/model/**'
DOC=docs/conventions/pr-pipeline/pr-run-activity.md
SHA_RE='^[0-9a-f]{40}$'
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
BY_VERSION=(-t. '-k1.2,1n' '-k2,2n' '-k3,3n')

die() {
  echo "::error::$*" >&2
  exit 1
}

out() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "$1" >>"$GITHUB_OUTPUT"; else echo "$1"; fi
}

file_set() {
  local root="$1" f
  for f in "$root"/.github/workflows/*.yml; do
    [[ "${f#"$root"/}" == "$MANAGED" ]] || echo "${f#"$root"/}"
  done
  echo "$DOC"
}

resolve() {
  local releases tag ref sha
  # shellcheck disable=SC2310 # the || handles gh's failure
  releases="$(gh api --paginate "repos/${UPSTREAM}/releases" \
    --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name')" ||
    die "could not read the published ${UPSTREAM} releases"
  tag="$(grep -E "$TAG_RE" <<<"$releases" | sort "${BY_VERSION[@]}" | tail -n1 || true)"
  [[ -n "$tag" ]] || die "no published ${UPSTREAM} release has a vX.Y.Z tag"
  ref="$(gh api "repos/${UPSTREAM}/git/ref/tags/${tag}" --jq '[.object.type, .object.sha] | @tsv')"
  case "${ref%%$'\t'*}" in
    tag) sha="$(gh api "repos/${UPSTREAM}/git/tags/${ref##*$'\t'}" --jq .object.sha)" ;;
    commit) sha="${ref##*$'\t'}" ;;
    *) die "tag ${tag} points at a '${ref%%$'\t'*}' object" ;;
  esac
  [[ "$sha" =~ $SHA_RE ]] || die "tag ${tag} resolved to '${sha}', not a commit SHA"
  echo "Resolved ${tag} to ${sha}."
  out "tag=${tag}"
  out "sha=${sha}"
}

current_pin() {
  local root="$1" files pins
  files="$(file_set "$root")"
  pins="$(cd "$root" && xargs grep -ohE \
    "${UPSTREAM}/\.github/actions/[^@ ]+@[0-9a-f]{40} # v[^ ]+" <<<"$files" 2>/dev/null |
    sed -E 's/.*@([0-9a-f]{40}) # (v[^ ]+)$/\1 \2/' | sort -u || true)"
  [[ -n "$pins" ]] || die "no ci-workflows action pin found under ${root}/.github/workflows"
  [[ "$(wc -l <<<"$pins")" -eq 1 ]] || die "the workflows pin more than one ci-workflows commit: $(tr '\n' ',' <<<"$pins")"
  echo "$pins"
}

current() {
  local pin
  pin="$(current_pin "$1")"
  out "sha=${pin%% *}"
  out "tag=${pin##* }"
}

apply() {
  local old="$1" old_tag="$2" new="$3" new_tag="$4" root="$5" files pin status f left outside rewritten
  [[ "$old" =~ $SHA_RE && "$new" =~ $SHA_RE ]] || die "old and new must be 40-character commit SHAs"
  [[ "$old_tag" =~ $TAG_RE && "$new_tag" =~ $TAG_RE ]] || die "old and new tags must be vX.Y.Z"
  pin="$(current_pin "$root")"
  [[ "$pin" == "${old} ${old_tag}" ]] || die "the workflows pin ${pin}, not ${old} ${old_tag}"
  if [[ "$old" == "$new" && "$old_tag" == "$new_tag" ]]; then
    echo "Already at ${new_tag}."
    out "changed=false"
    return 0
  fi
  [[ "$old_tag" != "$new_tag" && "$(printf '%s\n' "$old_tag" "$new_tag" | sort "${BY_VERSION[@]}" | tail -n1)" == "$new_tag" ]] ||
    die "${new_tag} is not newer than the current pin ${old_tag}"
  # shellcheck disable=SC2310 # the || handles gh's failure
  status="$(gh api "repos/${UPSTREAM}/compare/${old}...${new}" --jq .status)" ||
    die "could not compare ${old}...${new} on ${UPSTREAM}"
  [[ "$status" == ahead ]] || die "${new_tag} (${new}) does not contain the current pin ${old}: compare status '${status}'"

  files="$(file_set "$root")"
  rewritten="$(mktemp)"
  while IFS= read -r f; do
    sed -E \
      -e "s#(${UPSTREAM}/\.github/actions/[^@ ]+)@${old} \# ${old_tag//./\\.}\$#\1@${new} \# ${new_tag}#" \
      -e "s#^([[:space:]]+ref: )${old} \# ${old_tag//./\\.}\$#\1${new} \# ${new_tag}#" \
      -e "s#(github\.com/${UPSTREAM}/blob/)${old}/#\1${new}/#g" \
      "$root/$f" >"$rewritten"
    cmp -s "$rewritten" "$root/$f" || cat "$rewritten" >"$root/$f"
  done <<<"$files"
  rm -f "$rewritten"

  left="$(git -C "$root" grep -l "$old" -- . ":(exclude)${MANAGED}" ":(exclude,glob)${FORMAL_MODELS}" || true)"
  [[ -z "$left" ]] || die "${old} still appears after the rewrite in: $(tr '\n' ' ' <<<"$left")"
  outside="$(git -C "$root" status --porcelain | cut -c4- | grep -vxF "$files" || true)"
  [[ -z "$outside" ]] || die "paths outside the re-pin set changed: $(tr '\n' ' ' <<<"$outside")"
  echo "Moved ${old_tag} (${old}) to ${new_tag} (${new})."
  out "changed=true"
}

main() {
  local cmd="${1:-}" root
  shift || true
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local args=()
  while (($#)); do
    if [[ "$1" == --root ]]; then
      root="$(cd "$2" && pwd)"
      shift 2
    else
      args+=("$1")
      shift
    fi
  done
  case "$cmd" in
    resolve) resolve ;;
    current) current "$root" ;;
    apply)
      ((${#args[@]} == 4)) || die "usage: apply <old-sha> <old-tag> <new-sha> <new-tag> [--root <dir>]"
      apply "${args[@]}" "$root"
      ;;
    *)
      echo "usage: $0 resolve | current [--root <dir>] | apply <old-sha> <old-tag> <new-sha> <new-tag> [--root <dir>]" >&2
      exit 2
      ;;
  esac
}

main "$@"
