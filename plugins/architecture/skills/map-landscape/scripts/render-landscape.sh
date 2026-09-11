#!/usr/bin/env bash
# Render the landscape artifacts from the committed record.
#
# WHY. Table rows, dependency truncation, diagram alias sanitising, boundary
# grouping and node labels are all mechanical, and rendering them by hand makes
# two runs on identical facts produce different files. Everything this script
# does is decided by the record: nothing here weighs, judges, or describes. Prose
# comes from the annotations file, written by a person or a model, and this
# script only appends it.
#
# Usage:
#   render-landscape.sh --record <landscape.json> --out <dir> [options]
#   render-landscape.sh --help
#
# Options:
#   --record <file>     The landscape record. Required.
#   --out <dir>         Directory the artifacts are written into. Required.
#   --dialect <name>    mermaid (default) or structurizr.
#   --notes <file>      Annotations appended verbatim to the landscape artifact.
#   --top-external <N>  How many external systems the diagram draws, most
#                       referenced first (default 5). Every internal system is
#                       always drawn. The remainder is counted in a line under
#                       the diagram, and stays in the record and the portfolio.
#
# Writes, into <dir>:
#
#   landscape.md   with --dialect mermaid: a `C4Context` block used without a
#                  focal system, one `System` per internal repository inside an
#                  `Enterprise_Boundary` per owner, one `System_Ext` per external
#                  repository, and one `Rel` per drawn edge.
#   landscape.dsl  with --dialect structurizr: a `workspace` whose `model` holds
#                  the same systems, grouped by owner, plus a `systemLandscape`
#                  view.
#   portfolio.md   the application-portfolio table, one row per repository in
#                  the record, sorted by name.
#
# Determinism is the contract: the same record and flags produce byte-identical
# files, so a re-run shows a diff only when the facts moved.
#
# Portability: bash plus POSIX awk/grep/sed. No jq, no `grep -P`, no python.
#
# Exit: 0 = written; 1 = the record is unreadable or not schema_version 1, or
# the output directory does not exist; 2 = usage.
set -uo pipefail

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

die() {
  printf 'render-landscape.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
outdir=""
dialect="mermaid"
notes=""
top_external=5

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --record)
    [[ $# -ge 2 ]] || die "--record needs a path" 2
    record="$2"
    shift 2
    ;;
  --record=*)
    record="${1#--record=}"
    shift
    ;;
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    outdir="$2"
    shift 2
    ;;
  --out=*)
    outdir="${1#--out=}"
    shift
    ;;
  --dialect)
    [[ $# -ge 2 ]] || die "--dialect needs a value" 2
    dialect="$2"
    shift 2
    ;;
  --dialect=*)
    dialect="${1#--dialect=}"
    shift
    ;;
  --notes)
    [[ $# -ge 2 ]] || die "--notes needs a path" 2
    notes="$2"
    shift 2
    ;;
  --notes=*)
    notes="${1#--notes=}"
    shift
    ;;
  --top-external)
    [[ $# -ge 2 ]] || die "--top-external needs a number" 2
    top_external="$2"
    shift 2
    ;;
  --top-external=*)
    top_external="${1#--top-external=}"
    shift
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

[[ -n "$record" && -n "$outdir" ]] || {
  usage >&2
  exit 2
}
case "$dialect" in
mermaid | structurizr) ;;
*) die "unknown dialect: $dialect (mermaid or structurizr)" 2 ;;
esac
case "$top_external" in
'' | *[!0-9]*) die "--top-external needs a whole number, got: $top_external" 2 ;;
*) ;;
esac
[[ -r "$record" ]] || die "cannot read record: $record" 1
[[ -d "$outdir" ]] || die "not a directory: $outdir" 1
[[ -z "$notes" || -r "$notes" ]] || die "cannot read notes: $notes" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$record" ||
  die "not a schema_version 1 record: $record" 1

# The top-level key/value split, shared with landscape-record.sh: it walks the
# object rather than matching a pattern, so a value carrying a brace, a comma or
# an escaped quote does not split the record in the wrong place.
read -r -d '' SPLIT_AWK <<'AWK' || true
function split_object(line, keys, vals,   i, n, c, k, v, depth, instr, start) {
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
# A JSON string array to a plain list, "" when empty.
function arraylist(v, sep,   inner, parts, n, i, out) {
  gsub(/^\[|\]$/, "", v)
  if (v == "") return ""
  n = split(v, parts, "\",\"")
  out = ""
  for (i = 1; i <= n; i++) {
    inner = parts[i]
    gsub(/^"|"$/, "", inner)
    out = out (i > 1 ? sep : "") inner
  }
  return out
}
function arraycount(v,   parts) {
  gsub(/^\[|\]$/, "", v)
  if (v == "") return 0
  return split(v, parts, "\",\"")
}
AWK

# --- The shared node and edge model ----------------------------------------
#
# Both renderers read the same three streams, so a system drawn in one dialect
# is the same system in the other.
#
#   node<TAB>alias<TAB>owner/repo<TAB>display<TAB>relation<TAB>description<TAB>owner
#   edge<TAB>from-alias<TAB>to-alias<TAB>label<TAB>relation
#   omit<TAB>external-systems-not-drawn

model="$(awk -v top="$top_external" "$SPLIT_AWK"'
function alias(s,   a) {
  a = s
  gsub(/[^A-Za-z0-9]/, "_", a)
  if (a ~ /^[0-9]/) a = "n_" a
  return a
}
function primary(list,   parts) {
  split(list, parts, ",")
  return parts[1]
}
/^[[:space:]]*\{"name":/ {
  name = unquote(field($0, "name"))
  owner = unquote(field($0, "owner"))
  key = (owner == "unknown" || owner == "" ? name : owner "/" name)
  run = unquote(field($0, "runtime"))
  fw = unquote(field($0, "target_framework"))
  desc = primary(run)
  if (fw != "unknown" && fw != "") desc = desc ", " fw
  if (desc == "unknown" || desc == "") desc = "no probed runtime"
  order[++ln] = key
  ldesc[key] = desc
  ldisp[key] = name
  localkey[name] = key
  next
}
/^[[:space:]]*\{"from":/ {
  from = unquote(field($0, "from"))
  to = unquote(field($0, "to"))
  type = unquote(field($0, "type"))
  rel = unquote(field($0, "relation"))
  cnt = unquote(field($0, "count")) + 0
  ++en
  efrom[en] = from
  etarget[en] = to
  elabel[en] = type " (" cnt ")"
  erel[en] = rel
  if (!(to in seen)) { seen[to] = 1; tos[++tn] = to }
  torel[to] = rel
  weight[to] += cnt
  next
}
END {
  # Every locally collected repository is a node, keyed by owner/name.
  for (i = 1; i <= ln; i++) {
    k = order[i]
    isnode[k] = 1
    nrel[k] = "internal"
    ndesc[k] = ldesc[k]
    ndisp[k] = ldisp[k]
  }
  # Edge targets that are not local checkouts become nodes with no probed facts.
  for (i = 1; i <= tn; i++) {
    k = tos[i]
    if (k in isnode) continue
    isnode[k] = 1
    nrel[k] = torel[k]
    ndesc[k] = "not checked out here"
    # Inside an owner boundary the owner prefix is redundant, so an internal
    # system shows its bare repository name and an external shows owner/repo.
    ndisp[k] = k
    if (nrel[k] == "internal") {
      split(k, oseg, "/")
      if (oseg[2] != "") ndisp[k] = oseg[2]
    }
  }
  # Drawn set: every internal node, and the most referenced externals.
  ni = 0
  ne = 0
  for (k in isnode) {
    if (nrel[k] == "internal") ints[++ni] = k
    else exts[++ne] = k
  }
  # Sort internals by display name, externals by weight then name; both without
  # calling out to sort(1), so the ordering here is stable and self-contained.
  # Internals sort by owner FIRST so each owner forms one contiguous run and the
  # boundary opened for it is never reopened further down the list.
  for (i = 1; i <= ni; i++) {
    split(ints[i], oseg, "/")
    sortkey[ints[i]] = (oseg[2] == "" ? "unknown" : oseg[1]) "\t" ndisp[ints[i]]
  }
  for (i = 1; i <= ni; i++)
    for (j = i + 1; j <= ni; j++)
      if (sortkey[ints[j]] < sortkey[ints[i]]) { t = ints[i]; ints[i] = ints[j]; ints[j] = t }
  for (i = 1; i <= ne; i++)
    for (j = i + 1; j <= ne; j++) {
      a = exts[i]; b = exts[j]
      if (weight[b] > weight[a] || (weight[b] == weight[a] && b < a)) { exts[i] = b; exts[j] = a }
    }
  for (i = 1; i <= ni; i++) drawn[ints[i]] = 1
  shown_ext = (top < ne ? top : ne)
  for (i = 1; i <= shown_ext; i++) drawn[exts[i]] = 1
  for (i = 1; i <= ni; i++) {
    k = ints[i]
    split(k, seg, "/")
    printf "node\t%s\t%s\t%s\t%s\t%s\t%s\n", alias(k), k, ndisp[k], "internal", ndesc[k], (seg[2] == "" ? "unknown" : seg[1])
  }
  for (i = 1; i <= shown_ext; i++) {
    k = exts[i]
    split(k, seg, "/")
    printf "node\t%s\t%s\t%s\t%s\t%s\t%s\n", alias(k), k, ndisp[k], "external", ndesc[k], (seg[2] == "" ? "unknown" : seg[1])
  }
  for (i = 1; i <= en; i++) {
    if (!(etarget[i] in drawn)) continue
    # The edge source names a checkout by basename, so resolve it through the
    # map the repository pass built. Iterating the node array instead would put
    # the answer at the mercy of the unspecified array order in awk.
    fk = localkey[efrom[i]]
    if (fk == "" || !(fk in isnode)) continue
    printf "edge\t%s\t%s\t%s\t%s\n", alias(fk), alias(etarget[i]), elabel[i], erel[i]
  }
  printf "omit\t%d\n", ne - shown_ext
}
' "$record")"

gen_on="$(sed -n 's/^[[:space:]]*"generated_on"[[:space:]]*:[[:space:]]*"\(.*\)".*$/\1/p' "$record" | head -1)"
disco="$(sed -n 's/^[[:space:]]*"discovery_source"[[:space:]]*:[[:space:]]*"\(.*\)".*$/\1/p' "$record" | head -1)"
remote_state="$(sed -n 's/^[[:space:]]*"remote"[[:space:]]*:[[:space:]]*"\(.*\)".*$/\1/p' "$record" | head -1)"
[[ -n "$gen_on" ]] || gen_on="unknown"
[[ -n "$disco" ]] || disco="unknown"
[[ -n "$remote_state" ]] || remote_state="not used"

omit_ext="$(printf '%s\n' "$model" | awk -F'\t' '$1 == "omit" { print $2 }')"

# --- Artifact one, the landscape -------------------------------------------

if [[ "$dialect" == "mermaid" ]]; then
  target="$outdir/landscape.md"
  {
    printf '# System Landscape\n\n'
    printf 'Generated on %s from %s. Remote facts: %s.\n\n' \
      "$gen_on" "$disco" "$remote_state"
    printf 'Every fact traces to the file the probe named. Every edge is typed by the\n'
    printf 'syntax that carries it and labelled with how many references support it.\n'
    printf 'A system with no probed runtime is one this checkout names but does not\n'
    printf 'contain.\n\n'
    printf '```mermaid\nC4Context\n  title System Landscape\n'
    printf '%s\n' "$model" | awk -F'\t' '
      $1 == "node" && $5 == "internal" { owners[$7] = 1; io[++n] = $0 }
      $1 == "node" && $5 == "external" { eo[++m] = $0 }
      END {
        b = 0
        for (i = 1; i <= n; i++) {
          split(io[i], f, "\t")
          # An enterprise boundary is captioned with an organisation. "unknown"
          # is the absence of one, so a repository with no resolvable owner is
          # drawn at the top level rather than inside a boundary naming nothing.
          if (f[7] == "unknown") {
            if (cur != "") { print "  }"; cur = "" }
            printf "  System(%s, \"%s\", \"%s\")\n", f[2], f[4], f[6]
            continue
          }
          if (f[7] != cur) {
            if (cur != "") print "  }"
            printf "  Enterprise_Boundary(b%d, \"%s\") {\n", b++, f[7]
            cur = f[7]
          }
          printf "    System(%s, \"%s\", \"%s\")\n", f[2], f[4], f[6]
        }
        if (cur != "") print "  }"
        for (i = 1; i <= m; i++) {
          split(eo[i], f, "\t")
          printf "  System_Ext(%s, \"%s\", \"%s\")\n", f[2], f[4], f[6]
        }
      }
    '
    printf '\n'
    printf '%s\n' "$model" | awk -F'\t' '$1 == "edge" { printf "  Rel(%s, %s, \"%s\")\n", $2, $3, $4 }'
    printf '```\n'
    if [[ "$omit_ext" -gt 0 ]]; then
      printf '\n%s external repositories are referenced but not drawn; the record carries\nevery one of them.\n' "$omit_ext"
    fi
  } >"$target"
else
  target="$outdir/landscape.dsl"
  {
    printf 'workspace {\n  model {\n'
    printf '%s\n' "$model" | awk -F'\t' '
      $1 == "node" && $5 == "internal" { io[++n] = $0 }
      $1 == "node" && $5 == "external" { eo[++m] = $0 }
      END {
        for (i = 1; i <= n; i++) {
          split(io[i], f, "\t")
          # A group is captioned with an organisation. "unknown" is the absence
          # of one, so an ownerless repository sits outside every group.
          if (f[7] == "unknown") {
            if (cur != "") { print "    }"; cur = "" }
            printf "    %s = softwareSystem \"%s\" \"%s\"\n", f[2], f[4], f[6]
            continue
          }
          if (f[7] != cur) {
            if (cur != "") print "    }"
            printf "    group \"%s\" {\n", f[7]
            cur = f[7]
          }
          printf "      %s = softwareSystem \"%s\" \"%s\"\n", f[2], f[4], f[6]
        }
        if (cur != "") print "    }"
        for (i = 1; i <= m; i++) {
          split(eo[i], f, "\t")
          printf "    %s = softwareSystem \"%s\" \"%s\" \"External\"\n", f[2], f[4], f[6]
        }
      }
    '
    printf '%s\n' "$model" | awk -F'\t' '$1 == "edge" { printf "    %s -> %s \"%s\"\n", $2, $3, $4 }'
    printf '  }\n  views {\n    systemLandscape "landscape" {\n'
    printf '      include *\n      autoLayout\n    }\n'
    # Structurizr removed the internal/external `location` property, so a tag is
    # the only carrier left for that fact. Without a style to read it the tag
    # renders nothing, and the DSL artifact would lose a distinction the mermaid
    # one keeps through System versus System_Ext.
    printf '    styles {\n      element "External" {\n'
    printf '        background #999999\n        color #ffffff\n      }\n    }\n'
    printf '  }\n}\n'
  } >"$target"
fi

if [[ -n "$notes" ]]; then
  {
    printf '\n'
    cat "$notes"
  } >>"$target"
fi

# --- Artifact two, the portfolio table -------------------------------------

{
  printf '# Application portfolio\n\n'
  printf 'Generated on %s from %s. Remote facts: %s.\n\n' \
    "$gen_on" "$disco" "$remote_state"
  printf 'Last touched is the local HEAD of each checkout unless a remote fact says\n'
  # shellcheck disable=SC2016 # backticks are markdown code spans, not substitution.
  printf 'otherwise, so a stale checkout reports a stale date. `unknown` means no probe\n'
  printf 'could derive the value.\n\n'
  # shellcheck disable=SC2016 # backticks are markdown code spans, not substitution.
  printf '`Runtime` and `Dependencies` are runtime scope, what the repository runs on.\n'
  # shellcheck disable=SC2016 # backticks are markdown code spans, not substitution.
  printf '`Tooling` and the development-scope dependencies below the table are what it\n'
  printf 'is built with.\n\n'
  printf '| Repository | Owner | Target framework | Runtime | Dependencies | Tooling | Last touched |\n'
  printf '|---|---|---|---|---|---|---|\n'
  awk "$SPLIT_AWK"'
    function cell(v) { return (v == "" ? "unknown" : v) }
    function deplist(v,   n, list, parts, i, out) {
      n = arraycount(v)
      if (n == 0) return "(none)"
      list = arraylist(v, ", ")
      if (n <= 10) return list
      split(list, parts, ", ")
      out = ""
      for (i = 1; i <= 10; i++) out = out (i > 1 ? ", " : "") parts[i]
      return out " (+" (n - 10) ")"
    }
    /^[[:space:]]*\{"name":/ {
      rows[++n] = sprintf("| %s | %s | %s | %s | %s | %s | %s |", \
        unquote(field($0, "name")), \
        cell(unquote(field($0, "owner"))), \
        cell(unquote(field($0, "target_framework"))), \
        cell(gensub_commas(unquote(field($0, "runtime")))), \
        deplist(field($0, "dependencies")), \
        cell(gensub_commas(unquote(field($0, "tooling")))), \
        cell(unquote(field($0, "last_touched"))))
      keys[n] = unquote(field($0, "name"))
    }
    function gensub_commas(v) { gsub(/,/, ", ", v); return v }
    END {
      for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
          if (keys[j] < keys[i]) {
            t = keys[i]; keys[i] = keys[j]; keys[j] = t
            t = rows[i]; rows[i] = rows[j]; rows[j] = t
          }
      for (i = 1; i <= n; i++) print rows[i]
    }
  ' "$record"
  # Development-scope dependencies stay out of the table: they are the longest
  # list in the record and would push every other column off the page.
  dev_lines="$(awk "$SPLIT_AWK"'
    function deplist(v,   n, list, parts, i, out) {
      n = arraycount(v)
      if (n == 0) return ""
      list = arraylist(v, "`, `")
      if (n <= 10) return "`" list "`"
      split(list, parts, "`, `")
      out = ""
      for (i = 1; i <= 10; i++) out = out (i > 1 ? ", " : "") "`" parts[i] "`"
      gsub(/`+/, "`", out)
      return out " (+" (n - 10) ")"
    }
    /^[[:space:]]*\{"name":/ {
      d = deplist(field($0, "dev_dependencies"))
      if (d != "") rows[++n] = sprintf("- %s: %s", unquote(field($0, "name")), d)
    }
    END { for (i = 1; i <= n; i++) print rows[i] }
  ' "$record")"
  if [[ -n "$dev_lines" ]]; then
    printf '\n## Development-scope dependencies\n\n'
    printf 'Truncated to ten per repository; the record carries the full list.\n\n'
    printf '%s\n' "$dev_lines"
  fi
  printf '\n## Evidence\n\n'
  printf '| Repository | Fact | Source |\n|---|---|---|\n'
  awk "$SPLIT_AWK"'
    /^[[:space:]]*\{"name":/ {
      name = unquote(field($0, "name"))
      ev = field($0, "evidence")
      n = split_object(ev, k, v)
      for (i = 1; i <= n; i++) printf "| %s | %s | %s |\n", name, k[i], unquote(v[i])
    }
  ' "$record"
} >"$outdir/portfolio.md"

exit 0
