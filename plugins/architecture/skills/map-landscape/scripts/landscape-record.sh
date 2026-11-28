#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTS="$SCRIPT_DIR/portfolio-facts.sh"
EDGES="$SCRIPT_DIR/reference-edges.sh"
# shellcheck source=../../../lib/record-layout.sh
source "$SCRIPT_DIR/../../../lib/record-layout.sh"

usage() {
  cat <<'EOF'
Assemble the landscape record, or report drift against a committed one.
Usage: landscape-record.sh [options] <repo-path>...
  --edges-from <path>  repository whose tracked files supply the edges (default: first <repo-path>)
  --owner <owner>      owner deciding internal vs external (default: the edges-from origin owner)
  --source <text>      discovery source recorded verbatim
  --remote <text>      remote-facts status recorded verbatim
  --remote-facts <f>   fetched facts for repositories with no local checkout, one object per line
  --drift-against <f>  compare with committed record <f> and print a drift report
The record (stdout) is schema_version 1, one object per line.
Exit: 0 record emitted, or compared with no drift; 1 a path is not a readable git repository, or
the compared record is unreadable, not schema_version 1, or not one object per line; 2 usage;
3 drift found.
EOF
}

die() {
  printf 'landscape-record.sh: %s\n' "$1" >&2
  exit "$2"
}


repos=()
edges_from=""
owner=""
source_text="explicit list"
remote_text="not used"
remote_facts=""
compare_to=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --edges-from)
    [[ $# -ge 2 ]] || die "--edges-from needs a path" 2
    edges_from="$2"
    shift 2
    ;;
  --edges-from=*)
    edges_from="${1#--edges-from=}"
    shift
    ;;
  --owner)
    [[ $# -ge 2 ]] || die "--owner needs a value" 2
    owner="$2"
    shift 2
    ;;
  --owner=*)
    owner="${1#--owner=}"
    shift
    ;;
  --source)
    [[ $# -ge 2 ]] || die "--source needs a value" 2
    source_text="$2"
    shift 2
    ;;
  --source=*)
    source_text="${1#--source=}"
    shift
    ;;
  --remote)
    [[ $# -ge 2 ]] || die "--remote needs a value" 2
    remote_text="$2"
    shift 2
    ;;
  --remote=*)
    remote_text="${1#--remote=}"
    shift
    ;;
  --remote-facts)
    [[ $# -ge 2 ]] || die "--remote-facts needs a path" 2
    remote_facts="$2"
    shift 2
    ;;
  --remote-facts=*)
    remote_facts="${1#--remote-facts=}"
    shift
    ;;
  --drift-against)
    [[ $# -ge 2 ]] || die "--drift-against needs a path" 2
    compare_to="$2"
    shift 2
    ;;
  --drift-against=*)
    compare_to="${1#--drift-against=}"
    shift
    ;;
  -*)
    die "unknown option: $1" 2
    ;;
  *)
    repos+=("$1")
    shift
    ;;
  esac
done

[[ "${#repos[@]}" -gt 0 ]] || {
  usage >&2
  exit 2
}
[[ -x "$FACTS" || -r "$FACTS" ]] || die "collector not found: $FACTS" 1
[[ -x "$EDGES" || -r "$EDGES" ]] || die "collector not found: $EDGES" 1

[[ -n "$edges_from" ]] || edges_from="${repos[0]}"
[[ -d "$edges_from" ]] || die "not a directory: $edges_from" 1


facts_out="$(bash "$FACTS" "${repos[@]}")" || die "fact collection failed" 1

edge_args=("$edges_from")
[[ -n "$owner" ]] && edge_args+=(--owner "$owner")
edges_out="$(bash "$EDGES" "${edge_args[@]}")" || die "edge extraction failed" 1
subject_owner="$(bash "$EDGES" "${edge_args[@]}" --print-owner)" || die "owner resolution failed" 1
[[ -n "$subject_owner" ]] || subject_owner="unknown"

if [[ -n "$remote_facts" ]]; then
  [[ -r "$remote_facts" ]] || die "cannot read remote facts: $remote_facts" 1
  merged="$(printf '%s\n' "$facts_out" | awk '
    NR == FNR { if (NF) { local[++l] = $0; name[objname($0)] = 1 } ; next }
    NF {
      if ($0 !~ /^[[:space:]]*\{"name":/)
        { printf "line %d is not a repository object\n", FNR > "/dev/stderr"; bad = 1; next }
      n = objname($0)
      if (n in name) next
      name[n] = 1
      remote[++r] = n "\t" $0
    }
    function objname(s,   t) {
      t = s
      sub(/^[^{]*\{"name":[[:space:]]*"/, "", t)
      sub(/".*$/, "", t)
      return t
    }
    END {
      if (bad) exit 1
      for (i = 1; i <= l; i++) print local[i]
      # Sorted, so the record does not depend on the order the fetches
      # happened to come back in.
      for (i = 1; i <= r; i++)
        for (j = i + 1; j <= r; j++)
          if (remote[j] < remote[i]) { t = remote[i]; remote[i] = remote[j]; remote[j] = t }
      for (i = 1; i <= r; i++) { sub(/^[^\t]*\t/, "", remote[i]); print remote[i] }
    }
  ' - "$remote_facts")" || die "malformed remote facts: $remote_facts" 1
  facts_out="$merged"
fi


read -r -d '' SPLIT_AWK <<'AWK' || true
function unquote(v) {
  if (substr(v, 1, 1) == "\"") return substr(v, 2, length(v) - 2)
  return v
}
AWK
SPLIT_AWK="$(<"$SCRIPT_DIR/../../../lib/split-object.awk")"$'\n'"$SPLIT_AWK"

emit_array() {
  if [[ -z "$2" ]]; then
    printf '  "%s": []%s\n' "$1" "$3"
    return
  fi
  printf '  "%s": [\n' "$1"
  printf '%s\n' "$2" | awk '
    NF { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) printf "    %s%s\n", lines[i], (i < n ? "," : "")
    }
  '
  printf '  ]%s\n' "$3"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if [[ -z "$compare_to" ]]; then
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "generated_on": "%s",\n' "$(date -u +%Y-%m-%d)"
  printf '  "discovery_source": "%s",\n' "$(json_escape "$source_text")"
  printf '  "remote": "%s",\n' "$(json_escape "$remote_text")"
  printf '  "subject_owner": "%s",\n' "$(json_escape "$subject_owner")"
  emit_array repositories "$(printf '%s\n' "$facts_out" | awk "$SPLIT_AWK"'
    NF {
      n = split_object($0, k, v)
      out = "{"
      first = 1
      for (i = 1; i <= n; i++) {
        if (k[i] == "path") continue
        out = out (first ? "" : ",") "\"" k[i] "\":" v[i]
        first = 0
      }
      print out "}"
    }
  ')" ","
  emit_array edges "$edges_out" ""
  printf '}\n'
  exit 0
fi


[[ -r "$compare_to" ]] || die "cannot read record: $compare_to" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$compare_to" ||
  die "not a schema_version 1 record: $compare_to" 1

layout_problem="$(record_layout_problem "$compare_to")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout this script writes ($layout_problem); regenerate it: $compare_to" 1

old_repos="$(sed -n 's/^[[:space:]]*\({"name":.*}\),\{0,1\}$/\1/p' "$compare_to")"
old_edges="$(sed -n 's/^[[:space:]]*\({"from":.*}\),\{0,1\}$/\1/p' "$compare_to")"

drift=0
report=""
notes=""
say() {
  report="$report$1"$'\n'
  drift=1
}
note() {
  notes="$notes$1"$'\n'
}

compare_set() {
  local label="$1" keyexpr="$2"
  local old_keys new_keys
  # shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
  local keyprog='
    NF {
      n = split(e, parts, ",")
      k = ""
      for (i = 1; i <= n; i++) k = k (i > 1 ? "\t" : "") unquote(field($0, parts[i]))
      print k
    }
  '
  old_keys="$(printf '%s\n' "$3" | awk -v e="$keyexpr" "$SPLIT_AWK$keyprog" | sort)"
  new_keys="$(printf '%s\n' "$4" | awk -v e="$keyexpr" "$SPLIT_AWK$keyprog" | sort)"
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    grep -qxF -e "$line" <<<"$new_keys" ||
      say "  removed $label: ${line//$'\t'/ }"
  done <<<"$old_keys"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    grep -qxF -e "$line" <<<"$old_keys" ||
      say "  added $label: ${line//$'\t'/ }"
  done <<<"$new_keys"
}

report="$report"'Landscape drift, fresh collection versus '"$compare_to"$'\n'

dup_names() {
  printf '%s\n' "$1" | awk "$SPLIT_AWK"'
    NF { n = unquote(field($0, "name")); if (n != "") seen[n]++ }
    END { for (k in seen) if (seen[k] > 1) print k }
  ' | sort
}
while IFS= read -r dup; do
  [[ -n "$dup" ]] || continue
  say "  ambiguous repository identity: several checkouts are named $dup, so this comparison cannot tell them apart"
done < <(
  printf '%s\n%s\n' "$(dup_names "$old_repos")" "$(dup_names "$facts_out")" | sort -u
)

old_remote="$(sed -n 's/^[[:space:]]*"remote"[[:space:]]*:[[:space:]]*"\(.*\)".*$/\1/p' "$compare_to" | head -1)"
if [[ "$old_remote" != "$remote_text" ]]; then
  report="$report"'  NOT COMPARABLE: the committed record was built with remote "'"$old_remote"'" and this run declares "'"$remote_text"'".'$'\n'
  report="$report"'  Repositories present only in the record are reported below, but a posture mismatch, not their removal, may explain them.'$'\n'
fi

compare_set repository "name" "$old_repos" "$facts_out"
compare_set edge "to,type" "$old_edges" "$edges_out"

compare_fields() {
  local label="$1" idkey="$2" new_line id old_line changed c
  while IFS= read -r new_line; do
    [[ -n "$new_line" ]] || continue
    id="$(printf '%s' "$new_line" | awk -v k="$idkey" "$SPLIT_AWK"'{ print unquote(field($0, k)) }')"
    old_line="$(printf '%s\n' "$3" | grep -F "\"$idkey\":\"$id\"" | head -1)"
    [[ -n "$old_line" ]] || continue
    changed="$(printf '%s\n%s\n' "$old_line" "$new_line" | awk "$SPLIT_AWK"'
      NR == 1 { on = split_object($0, ok, ov) }
      NR == 2 { nn = split_object($0, nk, nv)
        for (i = 1; i <= nn; i++) {
          if (nk[i] == "path") continue
          for (j = 1; j <= on; j++) {
            if (ok[j] == nk[i]) {
              if (ov[j] != nv[i]) printf "%s: %s -> %s\n", nk[i], ov[j], nv[i]
              break
            }
          }
        }
      }
    ')"
    while IFS= read -r c; do
      [[ -n "$c" ]] || continue
      case "$c" in
      last_touched:*) note "  moved on $id: $c" ;;
      remote:*) note "  remote transport differs on $id: $c" ;;
      *) say "  changed $label on $id: $c" ;;
      esac
    done <<<"$changed"
  done <<<"$4"
}

compare_fields fact name "$old_repos" "$facts_out"

for t in uses-workflow installs-plugin depends-on cites; do
  compare_fields "edge ($t)" to \
    "$(printf '%s\n' "$old_edges" | grep -F "\"type\":\"$t\"")" \
    "$(printf '%s\n' "$edges_out" | grep -F "\"type\":\"$t\"")"
done

missing="$(printf '%s\n' "$old_edges" | awk "$SPLIT_AWK"'
  NF {
    to = unquote(field($0, "to"))
    files = field($0, "files")
    gsub(/^\[|\]$/, "", files)
    n = split(files, parts, "\",\"")
    for (i = 1; i <= n; i++) {
      f = parts[i]
      gsub(/^"|"$/, "", f)
      if (f != "") print to "\t" f
    }
  }
' | sort -u)"
while IFS=$'\t' read -r to f; do
  [[ -n "$f" ]] || continue
  [[ -e "$edges_from/$f" ]] || say "  missing evidence for $to: $f"
done <<<"$missing"

if [[ "$drift" -eq 0 ]]; then
  if [[ -z "$notes" ]]; then
    printf 'Landscape drift: none. The committed record matches a fresh collection.\n'
  else
    printf 'Landscape drift: none that gates. Non-gating differences follow.\n'
    printf '%s' "$notes"
  fi
  exit 0
fi

printf '%s' "$report"
[[ -z "$notes" ]] || printf '%s' "$notes"
exit 3
