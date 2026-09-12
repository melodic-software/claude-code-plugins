#!/usr/bin/env bash
# Assemble the committed landscape record, and report drift against an earlier one.
#
# WHY. Facts and edges are collected fresh on every run, so without a committed
# record a landscape is a snapshot with no memory: nothing tells the operator
# that a system appeared, an edge vanished, or a runtime changed since the last
# time anyone looked. This script is that memory. It composes the two collectors
# into one file the repository commits, and it compares a fresh collection with
# the committed one so a re-run reports what moved instead of silently
# overwriting the answer.
#
# Usage:
#   landscape-record.sh [options] <repo-path>...
#   landscape-record.sh --help
#
# Options:
#   --edges-from <path>  Repository whose tracked files supply the edges.
#                        Defaults to the first <repo-path>.
#   --owner <owner>      Passed to the edge extractor; decides internal vs
#                        external. Defaults to the edges-from origin owner.
#   --source <text>      Discovery source recorded verbatim in the record.
#   --remote <text>      Remote-facts status recorded verbatim in the record.
#   --remote-facts <f>   Merge fetched facts for repositories with no local
#                        checkout. One JSON object per line, each opening with
#                        "name", in the shape portfolio-facts.sh emits. A local
#                        checkout wins: an entry whose name a collector already
#                        produced is discarded, not merged field by field.
#   --drift-against <f>  Compare the fresh collection with committed record <f>.
#                        Prints a drift report instead of the record.
#
# Output without --drift-against: the record on stdout.
#
#   {
#     "schema_version": 1,
#     "generated_on": "YYYY-MM-DD",
#     "discovery_source": "…",
#     "remote": "…",
#     "subject_owner": "…",
#     "repositories": [ <one portfolio-facts object per line> ],
#     "edges": [ <one reference-edges object per line> ]
#   }
#
# `subject_owner` is the organisation the graph was drawn from, resolved by the
# edge extractor so the nodes and the edges cannot disagree about it. It is what
# makes a checkout internal: having a repository on disk says where someone
# works, not who owns the system.
#
# One object per line is deliberate: it keeps the record diffable in review and
# parseable here without a JSON library. The collector's `path` field is dropped
# on the way in: it records where a checkout happens to sit on one machine, which
# is not a fact about the architecture and would make the committed record differ
# on every machine that regenerates it.
#
# Output with --drift-against: a plain-text report naming repositories added or
# removed, edges added or removed, facts whose value changed, and cited evidence
# files that no longer exist. `path` is excluded from fact comparison too, so a
# record written before it was dropped still compares clean. A `last_touched`
# that moved is reported but never gated on: the subject repository advances its
# own HEAD on every commit, and a check lane that went red for that gets muted.
#
# Nothing here fetches and nothing is written: the record goes to stdout, and the
# caller decides where it lands.
#
# Portability: bash plus POSIX awk/grep/sed. No jq, no `grep -P`, no python.
#
# Exit: 0 = record emitted, or compared with no drift; 1 = a path is not a
# readable git repository, or the compared record is unreadable or not
# schema_version 1; 2 = usage; 3 = drift found.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTS="$SCRIPT_DIR/portfolio-facts.sh"
EDGES="$SCRIPT_DIR/reference-edges.sh"

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

die() {
  printf 'landscape-record.sh: %s\n' "$1" >&2
  exit "$2"
}

# --- Arguments --------------------------------------------------------------

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

# --- Collect ----------------------------------------------------------------

facts_out="$(bash "$FACTS" "${repos[@]}")" || die "fact collection failed" 1

edge_args=("$edges_from")
[[ -n "$owner" ]] && edge_args+=(--owner "$owner")
edges_out="$(bash "$EDGES" "${edge_args[@]}")" || die "edge extraction failed" 1
subject_owner="$(bash "$EDGES" "${edge_args[@]}" --print-owner)" || die "owner resolution failed" 1
[[ -n "$subject_owner" ]] || subject_owner="unknown"

# Fetched facts for repositories nobody has checked out. They arrive already
# assembled, because fetching them is model work against an API and this script
# reaches no network. A local checkout wins outright rather than field by field:
# a probe that read the files is a better witness than an API summary of them,
# and merging the two would produce a repository row no single source stands
# behind.
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

# --- Emit -------------------------------------------------------------------

# One top-level key/value split, shared by emission and comparison. Walks the
# object rather than matching a pattern, so a value carrying a brace, a comma or
# an escaped quote does not split the record in the wrong place.
read -r -d '' SPLIT_AWK <<'AWK' || true
function split_object(line, keys, vals,   i, n, c, k, v, depth, instr, esc, start) {
  n = 0
  i = index(line, "{")
  if (i == 0) return 0
  i++
  while (i <= length(line)) {
    c = substr(line, i, 1)
    if (c == " " || c == ",") { i++; continue }
    if (c == "}") break
    if (c != "\"") return n
    i++
    start = i
    while (i <= length(line)) {
      c = substr(line, i, 1)
      if (c == "\\") { i += 2; continue }
      if (c == "\"") break
      i++
    }
    k = substr(line, start, i - start)
    i++
    while (substr(line, i, 1) == " " || substr(line, i, 1) == ":") i++
    start = i
    c = substr(line, i, 1)
    if (c == "\"") {
      i++
      while (i <= length(line)) {
        c = substr(line, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "\"") break
        i++
      }
      i++
    } else if (c == "[" || c == "{") {
      depth = 0
      instr = 0
      while (i <= length(line)) {
        c = substr(line, i, 1)
        if (instr) {
          if (c == "\\") { i += 2; continue }
          if (c == "\"") instr = 0
        } else if (c == "\"") {
          instr = 1
        } else if (c == "[" || c == "{") {
          depth++
        } else if (c == "]" || c == "}") {
          depth--
          if (depth == 0) { i++; break }
        }
        i++
      }
    } else {
      while (i <= length(line) && substr(line, i, 1) != "," && substr(line, i, 1) != "}") i++
    }
    v = substr(line, start, i - start)
    n++
    keys[n] = k
    vals[n] = v
  }
  return n
}
function field(line, want,   keys, vals, n, i) {
  n = split_object(line, keys, vals)
  for (i = 1; i <= n; i++) if (keys[i] == want) return vals[i]
  return ""
}
function unquote(v) {
  if (substr(v, 1, 1) == "\"") return substr(v, 2, length(v) - 2)
  return v
}
AWK

emit_array() {
  # $1 the JSON key, $2 the newline-separated object lines, $3 the trailing
  # comma ("," for every array but the last).
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
  # `path` is dropped on the way in. It records where a checkout happened to sit
  # on one machine at one moment, which is not a fact about the architecture and
  # would make the committed record differ on every machine that regenerates it.
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

# --- Drift ------------------------------------------------------------------

[[ -r "$compare_to" ]] || die "cannot read record: $compare_to" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$compare_to" ||
  die "not a schema_version 1 record: $compare_to" 1

# The committed record's own arrays, one object per line, recovered by shape:
# a repository object opens with "name", an edge object with "from".
old_repos="$(sed -n 's/^[[:space:]]*\({"name":.*}\),\{0,1\}$/\1/p' "$compare_to")"
old_edges="$(sed -n 's/^[[:space:]]*\({"from":.*}\),\{0,1\}$/\1/p' "$compare_to")"

drift=0
report=""
notes=""
say() {
  report="$report$1"$'\n'
  drift=1
}
# A timestamp moving forward is expected of any repository anyone is working in,
# so it is reported and never gated on: a `--check` lane that went red on every
# commit to the subject repository would be turned off within a week.
note() {
  notes="$notes$1"$'\n'
}

compare_set() {
  # $1 label, $2 key expression, $3 old lines, $4 new lines
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
    printf '%s\n' "$new_keys" | grep -qxF "$line" ||
      say "  removed $label: ${line//$'\t'/ }"
  done <<<"$old_keys"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s\n' "$old_keys" | grep -qxF "$line" ||
      say "  added $label: ${line//$'\t'/ }"
  done <<<"$new_keys"
}

report="$report"'Landscape drift, fresh collection versus '"$compare_to"$'\n'

# A repository is identified by `name`, its directory basename. Two checkouts
# sharing a basename would collapse onto one key here and silently match the
# wrong row below, so an ambiguous identity is reported rather than guessed at.
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

# The committed record and this collection must describe the same kind of
# thing. A record built with remote facts carries repositories no local-only
# run can produce, and every one of them would otherwise report as removed.
old_remote="$(sed -n 's/^[[:space:]]*"remote"[[:space:]]*:[[:space:]]*"\(.*\)".*$/\1/p' "$compare_to" | head -1)"
if [[ "$old_remote" != "$remote_text" ]]; then
  report="$report"'  NOT COMPARABLE: the committed record was built with remote "'"$old_remote"'" and this run declares "'"$remote_text"'".'$'\n'
  report="$report"'  Repositories present only in the record are reported below, but a posture mismatch, not their removal, may explain them.'$'\n'
fi

compare_set repository "name" "$old_repos" "$facts_out"
compare_set edge "to,type" "$old_edges" "$edges_out"

# Field-level comparison for records present in both collections. `path` is
# skipped: it says where a checkout sits on one machine, not what the system is.
compare_fields() {
  # $1 label, $2 identity key, $3 old lines, $4 new lines
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
      *) say "  changed $label on $id: $c" ;;
      esac
    done <<<"$changed"
  done <<<"$4"
}

compare_fields fact name "$old_repos" "$facts_out"

# An edge is identified by its target and type together, so the field pass runs
# per type rather than collapsing two edges to the same repository into one.
for t in uses-workflow installs-plugin depends-on cites; do
  compare_fields "edge ($t)" to \
    "$(printf '%s\n' "$old_edges" | grep -F "\"type\":\"$t\"")" \
    "$(printf '%s\n' "$edges_out" | grep -F "\"type\":\"$t\"")"
done

# Evidence the COMMITTED record cites that is no longer in the checkout. Reading
# the committed side is the point: a fresh collection can only ever cite files
# that exist, so checking it would find nothing by construction.
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
    # Saying the record "matches" and then listing what moved contradicts
    # itself. Non-gating lines are still differences; only their consequence
    # differs.
    printf 'Landscape drift: none that gates. Non-gating differences follow.\n'
    printf '%s' "$notes"
  fi
  exit 0
fi

printf '%s' "$report"
[[ -z "$notes" ]] || printf '%s' "$notes"
exit 3
