#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$SCRIPT_DIR/../../../tools/work-item-tracker/work-item-tracker.sh"
CONFIG="docs/conventions/pr-pipeline.yaml"
PREFIX="models.issue-dimensions.fields."

die() {
  printf 'set-dimensions: %s\n' "$2" >&2
  exit "$1"
}

ref="" dry_run=0 id="" pairs=()
while (($#)); do
  case "$1" in
  --ref)
    (($# >= 2)) || die 2 "--ref needs a value"
    ref="$2"
    shift
    ;;
  --dry-run) dry_run=1 ;;
  -h | --help)
    cat <<'TXT'
Set an item's issue dimensions from the keys triage chose, through the tracker seam.

Usage: set-dimensions.sh [--ref <ref>] [--dry-run] <item-id> <dimension>=<key> ...
  <dimension>=<key>  one per dimension the models.issue-dimensions.fields block names
  --ref <ref>        read the block as committed at <ref> (a 40-hex commit id or origin/<name>)
  --dry-run          print the resolved ids and write nothing
  --help             print this help

Exit 0 written (or resolved under --dry-run); 1 an unparsable config; 2 usage error, unmapped key or bad --ref; 3 no dimension map; otherwise the seam's exit code.
TXT
    exit 0
    ;;
  *=*) pairs+=("$1") ;;
  *)
    [[ -z "$id" ]] || die 2 "unexpected argument: $1"
    id="$1"
    ;;
  esac
  shift
done
[[ -n "$id" && ${#pairs[@]} -gt 0 ]] || die 2 "usage: set-dimensions.sh [--ref <ref>] [--dry-run] <item-id> <dimension>=<key> ..."

if [[ -n "$ref" ]]; then
  [[ "$ref" =~ ^[0-9a-f]{40}$ || ("$ref" =~ ^origin/[A-Za-z0-9._/-]+$ && "$ref" != *..* && "$ref" != origin/-*) ]] ||
    die 2 "invalid --ref; expected a 40-hex commit id or origin/<name>"
  git rev-parse --verify --quiet --end-of-options "$ref^{commit}" >/dev/null || die 2 "--ref does not resolve to a commit: $ref"
  text="$(git show --end-of-options "$ref:$CONFIG" 2>/dev/null)" || text=""
else
  text="$(cat "$CONFIG" 2>/dev/null)" || text=""
fi
records="$(LC_ALL=C awk -f "$SCRIPT_DIR/yaml-subset.awk" <<<"$text")" ||
  die 1 "$CONFIG does not parse: $(awk -F '\t' '$1 == "error" { print "line " $2 ": " $3 }' <<<"$records")"
records="$(awk -F '\t' -v p="$PREFIX" 'index($1, p) == 1 { print substr($0, length(p) + 1) }' <<<"$records")"
[[ -n "$records" ]] || die 3 "$CONFIG has no ${PREFIX%.} block"

dims="$(awk -F '\t' '{ split($1, k, "."); if (k[2] == "field-id") print k[1] }' <<<"$records" | sort -u)"
given=""
fields=()
rows=""
for pair in "${pairs[@]}"; do
  dim="${pair%%=*}" key="${pair#*=}"
  grep -qxF -- "$dim" <<<"$dims" || die 2 "$CONFIG maps no dimension $dim"
  grep -qxF -- "$dim" <<<"$given" && die 2 "dimension $dim given twice"
  given+="$dim"$'\n'
  field_id="$(awk -F '\t' -v k="$dim.field-id" '$1 == k { print $2 }' <<<"$records")"
  options="$(awk -F '\t' -v p="$dim.options." -v key="$key" 'index($1, p) == 1 && $2 == key { print substr($1, length(p) + 1) }' <<<"$records")"
  count="$(grep -c . <<<"$options")"
  ((count == 1)) || die 2 "$count options of $dim map to key '$key' in $CONFIG; need exactly one"
  fields+=(--field "$field_id=$options")
  rows+="$(jq -nc --arg d "$dim" --arg k "$key" --argjson f "$field_id" --argjson o "$options" \
    '{dimension: $d, key: $k, field_id: $f, option_id: $o}')"$'\n'
done
while IFS= read -r dim; do
  grep -qxF -- "$dim" <<<"$given" || die 2 "no key given for dimension $dim"
done <<<"$dims"

if ((dry_run)); then
  jq -sc --arg id "$id" '{id: $id, fields: .}' <<<"$rows"
  exit 0
fi
exec bash "$TRACKER" set-fields "$id" "${fields[@]}"
