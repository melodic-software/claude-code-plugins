#!/usr/bin/env bash
# Build the conversation comment `reassess --act` posts on a rework or close.
#
# The text is fixed and every value is a reference: no PR or issue text, local
# path or free wording reaches a public comment, so it cannot mention anyone,
# leak local data or read as a person's veto.
#
# Usage:
#   reassess-comment.sh --verdict <rework|close> [--replaced-by <ref>] [--no-label] --evidence <ref>...
#
# A <ref> is a full https://github.com/ URL, a commit SHA, or #<number>.
# --no-label is for a close where the label does not exist, so the comment
# claims no hold.
#
# Exit 0, or 2 for a usage error (stdout empty).
set -uo pipefail

die() {
  printf 'reassess-comment: %s\n' "$1" >&2
  exit 2
}

check_ref() {
  [[ "$1" =~ ^(https://github\.com/[A-Za-z0-9._/-]+(#[A-Za-z0-9_-]+)?|[0-9a-f]{7,40}|#[0-9]+)$ ]] ||
    die "not a reference: $(printf '%q' "$1")"
}

verdict="" replaced="" evidence=() label=1
while (($# > 0)); do
  case "$1" in
  --no-label)
    label=0
    shift
    ;;
  --verdict | --replaced-by | --evidence)
    (($# >= 2)) || die "$1 needs a value"
    [[ "$1" == --verdict ]] || check_ref "$2"
    case "$1" in
    --verdict) verdict="$2" ;;
    --replaced-by) replaced="$2" ;;
    *) evidence+=("$2") ;;
    esac
    shift 2
    ;;
  *) die "unexpected argument $(printf '%q' "$1")" ;;
  esac
done

((${#evidence[@]} > 0)) || die "at least one --evidence is required"
case "$verdict" in
rework)
  [[ -z "$replaced" ]] || die "--replaced-by is for a close"
  summary="Reassessed: the goal still holds, and the implementation needs rework against the base."
  ;;
close)
  [[ -n "$replaced" ]] || die "a close needs --replaced-by"
  summary="Reassessed: this change already landed, so the \`do-not-merge\` label now holds this pull request. Replaced by $replaced."
  ((label)) || summary="Reassessed: this change already landed. Replaced by $replaced."
  ;;
*) die "--verdict must be rework or close" ;;
esac

printf '<!-- source-control-reassess -->\n%s\n\nEvidence:\n\n' "$summary"
printf -- '- %s\n' "${evidence[@]}"
