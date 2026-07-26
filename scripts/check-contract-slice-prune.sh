#!/usr/bin/env bash
# Enforce the topic-docs contract-slice prune step.
#
#   scripts/check-contract-slice-prune.sh --check              fail if a baseline
#                                                              entry no longer
#                                                              names a slice that
#                                                              exists
#   scripts/check-contract-slice-prune.sh --check-diff <ref>   fail if the change
#                                                              set leaves any path
#                                                              under the contract
#                                                              dir added, edited,
#                                                              renamed-into, or
#                                                              copied-into
#
# docs/conventions/topic-docs/README.md specifies a required check that the net
# PR diff carries no path under the resolved contract dir (default docs/topics/).
# The convention was written but never wired, and 17 slices reached main as a
# result (#1417).
#
# Deletion is the exemption, not an oversight. The convention's own step 4 is a
# final commit that PRUNES the slice, so a literal "no path under docs/topics/
# appears in the diff" reading would red-line the very commit that satisfies the
# convention. This gate therefore keys on where a path LANDS, not on whether it
# appears: a diff may remove paths under the contract dir freely, and may
# `git mv` one OUT of it (that is step 3's history-preserving graduation), but it
# may not leave one behind.
#
# The convention formulates the check as `git diff --name-only base...head`.
# --name-only cannot distinguish a deletion from an addition, so this gate reads
# --name-status instead. That is a deliberate deviation from the letter of the
# convention in service of its intent; the three-dot base...HEAD range is
# unchanged.
#
# Existing debt is grandfathered by SLUG in scripts/contract-slice-baseline.txt
# (the same stale-guarded idiom as scripts/changelog-parity-baseline.txt and
# scripts/orphaned-fixtures-baseline.txt): --check-diff exempts a listed slug so
# the gate can land without red-lining the open PRs that already carry those
# paths, and --check fails on a STALE entry — one whose slice no longer exists —
# so an exemption cannot outlive the debt it covers. Graduating a slice is
# tracked as #1419; each slice's prune PR drops its own baseline line.
#
# The exemption set is read from the BASE revision, never from the working tree.
# A baseline read at head would let one PR add docs/topics/<slug>/ AND add <slug>
# to the baseline in the same diff, exempting itself — the gate would pass and
# the enforcement would be decorative. Reading the base revision means only debt
# that was already grandfathered before the change set can exempt anything, so a
# baseline addition grants nothing to the PR that makes it.
#
# contract_dir resolves from the tracked concern file .claude/topic-docs.yaml
# when present, per the resolution order in
# docs/conventions/topic-docs/README.md — that file is the runtime authority, so
# a repo that relocates its contract root must not silently fall back to
# docs/topics and leave the real root unchecked. Also read from the base
# revision, for the same self-exemption reason: relocating contract_dir in the
# same PR that adds a slice under the old root would otherwise dodge the gate.
#
# Fail-closed: an unresolvable base ref, a diff that cannot be computed, or a
# concern file present but unreadable exits non-zero rather than passing
# unchecked. CONTRACT_SLICE_DIR and CONTRACT_SLICE_BASELINE override the
# resolved contract dir and baseline path (test injection).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

CONCERN_FILE=".claude/topic-docs.yaml"
BASELINE="${CONTRACT_SLICE_BASELINE:-scripts/contract-slice-baseline.txt}"

# Read a repo path at <rev>, or from the working tree when rev is empty.
# Prints nothing and returns 1 when the path does not exist there.
read_at_rev() {
  local rev="$1" path="$2"
  if [[ -z "$rev" ]]; then
    [[ -f "$path" ]] || return 1
    cat -- "$path"
    return 0
  fi
  git show "$rev:$path" 2>/dev/null
}

# contract_dir from the concern file at <rev>, falling back to the documented
# default. Minimal scalar parse: the key is documented as a plain unquoted
# scalar with an optional trailing comment.
resolve_contract_dir() {
  local rev="$1" content value
  if ! content="$(read_at_rev "$rev" "$CONCERN_FILE")"; then
    printf 'docs/topics'
    return 0
  fi
  value="$(printf '%s\n' "$content" |
    sed -n 's/^[[:space:]]*contract_dir[[:space:]]*:[[:space:]]*//p' |
    head -n1 |
    sed 's/[[:space:]]*#.*$//; s/^["'"'"']//; s/["'"'"']$//; s/[[:space:]]*$//')"
  if [[ -z "$value" ]]; then
    printf 'docs/topics'
    return 0
  fi
  printf '%s' "$value"
}

mode="${1:-}"
case "$mode" in
--check | --check-diff) ;;
*)
  echo "usage: $(basename "$0") [--check | --check-diff <base-ref>]" >&2
  exit 2
  ;;
esac

# --check inspects the working tree (is any entry stale right now?), so it reads
# both the concern file and the baseline from the working tree. --check-diff
# judges a change set and therefore resolves both from the BASE revision, so the
# change set cannot widen its own exemptions. The base ref is validated below,
# before either is read.
baseline_rev=""
if [[ "$mode" == "--check-diff" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "usage: $(basename "$0") --check-diff <base-ref>" >&2
    exit 2
  fi
  if ! git rev-parse --verify --quiet "${2}^{commit}" >/dev/null; then
    echo "check-contract-slice-prune: base ref '$2' is not a resolvable commit." >&2
    exit 2
  fi
  baseline_rev="$2"
fi

CONTRACT_DIR="${CONTRACT_SLICE_DIR:-$(resolve_contract_dir "$baseline_rev")}"
CONTRACT_DIR="${CONTRACT_DIR%/}"
if [[ -z "$CONTRACT_DIR" || "$CONTRACT_DIR" == "." || "$CONTRACT_DIR" == "/" ]]; then
  echo "check-contract-slice-prune: resolved contract_dir is root-equivalent ('$CONTRACT_DIR'); refusing to run." >&2
  exit 2
fi

# Grandfathered slice slugs (directory names directly under the contract dir).
declare -A grandfathered
if baseline_content="$(read_at_rev "$baseline_rev" "$BASELINE")"; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    grandfathered["$line"]=1
  done <<<"$baseline_content"
fi

# Map a repo path to the slice slug that owns it, or empty if the path is not
# under the contract dir. "docs/topics/foo/design/x.md" -> "foo".
slug_of() {
  local path="$1"
  case "$path" in
  "$CONTRACT_DIR"/*)
    local rest="${path#"$CONTRACT_DIR"/}"
    printf '%s' "${rest%%/*}"
    ;;
  *) printf '' ;;
  esac
}

if [[ "$mode" == "--check" ]]; then
  stale=0
  for slug in "${!grandfathered[@]}"; do
    if [[ ! -d "$CONTRACT_DIR/$slug" ]]; then
      echo "STALE BASELINE: '$slug' in $BASELINE no longer names a slice under $CONTRACT_DIR/ — remove the line." >&2
      stale=1
    fi
  done
  if ((stale)); then
    echo "" >&2
    echo "A baseline entry outliving its slice would silently re-open the exemption for a future slice reusing that slug." >&2
    exit 1
  fi
  echo "Every $BASELINE entry still names an existing slice under $CONTRACT_DIR/ ($(("${#grandfathered[@]}")) grandfathered)."
  exit 0
fi

# --check-diff mode (argument and base ref already validated above)
base="$2"

# Three-dot base...HEAD is diff(merge-base(base,HEAD), HEAD) — only the commits
# unique to this branch. A slice that main gained after this branch forked is
# therefore out of scope, so an untouched stale branch is never forced to
# merge-from-main over someone else's violation.
#
# Read via COMMAND substitution, not process substitution: this is a required
# merge check and a git failure must fail loud. Process substitution swallows
# git's exit status, so a diff that genuinely cannot be computed (no common
# ancestor -> "fatal: no merge base", exit 128) would yield empty output and let
# the gate exit 0 without checking anything. A legitimate empty diff succeeds
# with empty output and correctly finds no violations.
if ! diff_status="$(git diff --name-status --find-renames "$base...HEAD")"; then
  echo "check-contract-slice-prune: 'git diff --name-status $base...HEAD' failed (no common ancestor between '$base' and HEAD, or history not fetched deeply enough); refusing to pass without checking." >&2
  exit 2
fi

violations=()
exempted=()
while IFS=$'\t' read -r status path dest; do
  [[ -z "$status" ]] && continue
  # Rename and copy carry two paths; what matters is where the content LANDS, so
  # the destination is the path under test. The source side of a rename out of
  # the contract dir is a graduation (`git mv` to docs/adr/) and must pass.
  case "$status" in
  R* | C*) landed="$dest" ;;
  D) continue ;;
  *) landed="$path" ;;
  esac
  [[ -z "$landed" ]] && continue

  slug="$(slug_of "$landed")"
  [[ -z "$slug" ]] && continue

  if [[ -n "${grandfathered[$slug]:-}" ]]; then
    exempted+=("$landed")
  else
    violations+=("$status	$landed")
  fi
done <<<"$diff_status"

if ((${#violations[@]})); then
  echo "Contract-slice prune gate FAILED — this change set leaves ${#violations[@]} path(s) under $CONTRACT_DIR/:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "" >&2
  echo "$CONTRACT_DIR/<slug>/ is Contract tier per docs/conventions/topic-docs/README.md: committed on a task branch only, pruned before merge." >&2
  echo "Before merging, graduate the durable outcomes (ADR / spec / tracker item) and delete the slice — the deletion itself passes this gate." >&2
  echo "Adding the slug to $BASELINE will NOT help: exemptions are read from the base revision, so a baseline line added by this change set grants it nothing." >&2
  exit 1
fi

if ((${#exempted[@]})); then
  echo "Contract-slice prune gate passed — ${#exempted[@]} path(s) under $CONTRACT_DIR/ exempted by $BASELINE (see #1419)."
else
  echo "Contract-slice prune gate passed — this change set leaves no path under $CONTRACT_DIR/."
fi
exit 0
