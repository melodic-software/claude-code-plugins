#!/usr/bin/env bash
# Exit codes:
#   0  clean
#   1  findings
#   2  environment or usage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2

data_dir="$REPO_ROOT/plugins/engineering-concepts/data"
plugins_dir="$REPO_ROOT/plugins"
indexes=()

usage() {
  printf 'usage: %s [--check] [--data-dir DIR] [--plugins-dir DIR] [--index FILE]...\n' "${0##*/}" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
  --check) shift ;;
  --data-dir | --plugins-dir | --index)
    (($# >= 2)) || usage
    case "$1" in
    --data-dir) data_dir="$2" ;;
    --plugins-dir) plugins_dir="$2" ;;
    *) indexes+=("$2") ;;
    esac
    shift 2
    ;;
  *) usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  printf 'check-engineering-concepts: jq is required\n' >&2
  exit 2
}
for index in ${indexes[@]+"${indexes[@]}"}; do
  [[ -f "$index" ]] || {
    printf 'check-engineering-concepts: index not found: %s\n' "$index" >&2
    exit 2
  }
done

findings=0
finding() {
  printf '%s\n' "$1" >&2
  findings=$((findings + 1))
}

# Rows are tab-separated: R <at> <id> <owner>, A <at> <id> <alias>, E <at> <reason>.
# shellcheck disable=SC2016 # $f and $r are jq variables
JQ_ROWS='
  select(length > 0)
  | (try fromjson catch null) as $r
  | ($f + ":" + (input_line_number | tostring)) as $at
  | if ($r | type) != "object" then ["E", $at, "line is not a JSON object"]
    elif ($r.id | type) != "string" or ($r.id | length) == 0 then ["E", $at, "id is missing"]
    else ["R", $at, $r.id, ($r.owner // "" | tostring)],
      (($r.aliases // [])[]? | ["A", $at, $r.id, tostring])
    end
  | @tsv'

rows=""
records=0
shopt -s nullglob
if [[ -d "$data_dir" ]]; then
  for file in "$data_dir"/*.jsonl; do
    rows+="$(jq -R -r --arg f "$file" "$JQ_ROWS" "$file")"$'\n' || exit 2
  done
fi
shopt -u nullglob

set +e
dup_findings="$(awk -F'\t' '
  $1 == "E" { print $2 ": " $3; bad = 1 }
  $1 == "R" {
    key = tolower($3)
    if (key in id_at) { print $2 ": id \"" $3 "\" already has a record at " id_at[key]; bad = 1 }
    else id_at[key] = $2
    ids[key] = $3
  }
  $1 == "A" {
    key = tolower($4); n++
    a_at[n] = $2; a_id[n] = $3; a_key[n] = key; a_text[n] = $4
  }
  END {
    for (i = 1; i <= n; i++) {
      key = a_key[i]
      if (key in ids && tolower(a_id[i]) != key) {
        print a_at[i] ": alias \"" a_text[i] "\" is the id of another record"; bad = 1
      }
      if ((key in alias_of) && alias_of[key] != tolower(a_id[i])) {
        print a_at[i] ": alias \"" a_text[i] "\" is also claimed by record \"" alias_of[key] "\" at " alias_at[key]; bad = 1
      } else if (!(key in alias_of)) {
        alias_of[key] = tolower(a_id[i]); alias_at[key] = a_at[i]
      }
    }
    exit bad
  }' <<<"$rows")"
dup_status=$?
set -e
if ((dup_status != 0)); then
  while IFS= read -r line; do
    finding "$line"
  done <<<"$dup_findings"
fi

while IFS=$'\t' read -r kind at id owner; do
  [[ "$kind" == R ]] || continue
  records=$((records + 1))
  if [[ "$owner" == https://* ]]; then
    continue
  elif [[ "$owner" =~ ^/?([a-z0-9-]+):([a-z0-9-]+)$ ]]; then
    skill="$plugins_dir/${BASH_REMATCH[1]}/skills/${BASH_REMATCH[2]}/SKILL.md"
    [[ -f "$skill" ]] || finding "$at: owner \"$owner\" of \"$id\" names no skill: $skill does not exist"
  else
    finding "$at: owner \"$owner\" of \"$id\" is neither an https URL nor a <plugin>:<skill> name"
  fi
done <<<"$rows"

for index in ${indexes[@]+"${indexes[@]}"}; do
  set +e
  index_findings="$(awk -v f="$index" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    NR == 1 && $0 != "---" { print f ": no frontmatter: the first line must be ---"; bad = 1; fm = 2 }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 && $0 == "---" { fm = 2; if (!seen) { print f ": frontmatter lacks the standards-contract key"; bad = 1 }; next }
    fm == 1 && /^standards-contract:/ {
      seen = 1; v = trim(substr($0, 20)); q = sprintf("%c", 39)
      gsub("^[\"" q "]|[\"" q "]$", "", v)
      if (v !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { print f ": standards-contract \"" v "\" is not a semver (MAJOR.MINOR.PATCH)"; bad = 1 }
    }
    fm == 2 && !table && /^[ \t]*\|/ {
      table = 1; n = split($0, cell, "|"); header = ""
      for (i = 2; i < n || (i == n && trim(cell[i]) != ""); i++) header = header (header == "" ? "" : " | ") trim(cell[i])
      if (header != "Surface | Applies when | File") { print f ": table header is \"" header "\", want \"Surface | Applies when | File\""; bad = 1 }
      next
    }
    table == 1 { table = 2; if ($0 !~ /^[ \t]*\|[ \t:|-]+\|?[ \t]*$/) { print f ": the table header is not followed by a separator row"; bad = 1 } }
    END {
      if (fm == 1) { print f ": frontmatter is never closed with ---"; bad = 1 }
      if (!table) { print f ": no index table with the header | Surface | Applies when | File |"; bad = 1 }
      exit bad
    }' "$index")"
  index_status=$?
  set -e
  if ((index_status != 0)); then
    while IFS= read -r line; do
      finding "$line"
    done <<<"$index_findings"
  fi
done

((findings == 0)) || exit 1
printf 'check-engineering-concepts: ok (%d records, %d indexes)\n' "$records" "${#indexes[@]}"
