#!/usr/bin/env bash
# Collect an entity-relationship record from committed schema declarations.
#
# WHY. An ERD is a fact only when every box and every cardinality comes from a
# declaration in a named file. This script reads those declarations. It does
# not open a database connection, even when --live is passed: a live adapter
# is not shipped, and the record says so instead of drawing.
#
# Usage:
#   collect-data.sh [--repo <path>] [--out <file>] [--generated-on <date>] [--live]
#   collect-data.sh --help
#
# Tracked files only (`git ls-files`). Source tiers, first that is present wins
# the diagram. Every other shipped tier that is also present is compared, and
# a disagreement is a mismatch row, not a silent choice.
#
#   1. model      Prisma schema (*.prisma)
#   2. orm        Entity Framework fluent one-to-many and one-to-one chains, from Entity<T>() or from
#                 the one IEntityTypeConfiguration<T> class in a file (builder.HasOne/HasMany)
#   3. migration  SQL under a migrations directory (root or nested), replayed from a stated statement subset
#
# The EF reader takes HasOne/HasMany with a generic argument or, for one-to-many
# only, a lambda navigation (HasMany(e => e.Posts), HasOne(e => e.Blog)) whose
# target type comes from the property declared on the configured entity's class
# (ICollection/List/IList/IEnumerable/HashSet<T> for a collection, T or T? for a
# reference). The foreign key is one column, HasForeignKey("Col") or
# HasForeignKey(e => e.Col); HasPrincipalKey is one column the same way.
# Requiredness is IsRequired(), IsRequired(true) or IsRequired(false) and, when none is
# written, the foreign-key property's declared type on the dependent class: T?,
# Nullable<T> and string? are optional, a built-in value type is required.
# Unreadable: a composite key, a navigation with no single declared type, an
# IsRequired argument other than true or false, and a
# foreign key with no IsRequired whose property is undeclared or has any other
# type (a plain string is nullable or not by project setting).
#
# A recognized mechanism this script does not extract (Django models, SQLAlchemy
# columns, EF [ForeignKey] annotations, implicit
# Prisma many-to-many) refuses the record, as does an EF chain or an ALTER TABLE
# action it cannot read when that tier wins; stderr names what stopped the EF
# read. A losing tier it cannot read is a
# not-compared mismatch row. A shipped diagram plus an unread
# mechanism would be a partial read.
#
# Output: data-model.json, schema_version 1, one object per line.
#
#   {
#     "schema_version": 1,
#     "generated_on": "YYYY-MM-DD",
#     "subject": "<github.com origin repository name, else directory basename>",
#     "status": "drawn" | "refused",
#     "reason": "",
#     "source_tier": "model" | "orm" | "migration" | "none",
#     "source_tool": "prisma" | "ef-fluent" | "sql-migration" | "none",
#     "mechanisms": [ one {"name":...} object per line, or [] ],
#     "modules": [ one {"id":...} object per line, or [] ],
#     "entities": [ one {"id":...} object per line, or [] ],
#     "attributes": [ one {"entity":...} object per line, or [] ],
#     "relationships": [ one {"from":...} object per line, or [] ],
#     "mismatches": [ one {"kind":...} object per line, or [] ]
#   }
#
# Relationship "from" is the foreign-key entity. "to" is the referenced entity.
# cardinality is the mermaid token with the referenced entity on the left
# (||--o{ is one referenced row to zero-or-more foreign-key rows). A foreign key
# covered by a unique or primary-key column set is one-to-one: ||--o| when
# required, |o--o| when optional. "references" is the referenced column list,
# empty when the declaration does not name it. A composite foreign key with no
# unique column set inside it has no readable cardinality, so the record refuses
# with unknown-cardinality instead of drawing one-to-many.
#
# Portability: bash plus POSIX awk. No jq, no python, no database client.
#
# Exit: 0 = a record was written (including a refusal); 1 = the path is not a
# readable directory; 2 = usage.
set -uo pipefail

# shellcheck source=../../../lib/github-remote.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/github-remote.sh"

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'collect-data.sh: %s\n' "$1" >&2
  exit "$2"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

repo=""
out_file=""
generated_on=""
live=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --repo)
    [[ $# -ge 2 ]] || die "--repo needs a path" 2
    repo="$2"
    shift 2
    ;;
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    out_file="$2"
    shift 2
    ;;
  --generated-on)
    [[ $# -ge 2 ]] || die "--generated-on needs a value" 2
    generated_on="$2"
    shift 2
    ;;
  --live)
    live=1
    shift
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

[[ -n "$repo" ]] || repo="."
[[ -d "$repo" ]] || die "not a directory: $repo" 1
repo="$(cd "$repo" && pwd)" || die "unreadable: $repo" 1

if [[ -z "$generated_on" ]]; then
  generated_on="$(git -C "$repo" log -1 --format=%cs 2>/dev/null || true)"
  [[ -n "$generated_on" ]] || generated_on="unknown"
fi

subject="$(basename "$repo")"
remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
if name="$(github_repo_name "$remote")"; then
  subject="$name"
fi

write_record() {
  local status="$1" reason="$2" tier="$3" tool="$4"
  local mech_file="$5" module_file="$6" entity_file="$7" attr_file="$8" rel_file="$9" mismatch_file="${10}"
  local dest body
  body="$(
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "generated_on": "%s",\n' "$(json_escape "$generated_on")"
      printf '  "subject": "%s",\n' "$(json_escape "$subject")"
      printf '  "status": "%s",\n' "$(json_escape "$status")"
      printf '  "reason": "%s",\n' "$(json_escape "$reason")"
      printf '  "source_tier": "%s",\n' "$(json_escape "$tier")"
      printf '  "source_tool": "%s",\n' "$(json_escape "$tool")"
      emit_array mechanisms "$mech_file"
      printf ',\n'
      emit_array modules "$module_file"
      printf ',\n'
      emit_array entities "$entity_file"
      printf ',\n'
      emit_array attributes "$attr_file"
      printf ',\n'
      emit_array relationships "$rel_file"
      printf ',\n'
      emit_array mismatches "$mismatch_file"
      printf '\n}\n'
    }
  )"
  if [[ -n "$out_file" ]]; then
    dest="$(dirname "$out_file")"
    mkdir -p "$dest"
    printf '%s' "$body" >"$out_file"
  else
    printf '%s' "$body"
  fi
}

emit_array() {
  local key="$1" file="$2" line first=1
  if [[ ! -s "$file" ]]; then
    printf '  "%s": []' "$key"
    return
  fi
  printf '  "%s": [\n' "$key"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if [[ $first -eq 1 ]]; then
      first=0
    else
      printf ',\n'
    fi
    printf '    %s' "$line"
  done <"$file"
  printf '\n  ]'
}

empty_tsvs() {
  : >"$1"
  : >"$2"
  : >"$3"
  : >"$4"
  : >"$5"
  : >"$6"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MECH="$TMP/mechanisms.tsv"
MODS="$TMP/modules.tsv"
ENTS="$TMP/entities.tsv"
ATTRS="$TMP/attributes.tsv"
RELS="$TMP/relationships.tsv"
MISMATCHES="$TMP/mismatches.tsv"
empty_tsvs "$MECH" "$MODS" "$ENTS" "$ATTRS" "$RELS" "$MISMATCHES"

refuse() {
  local reason="$1"
  write_record refused "$reason" none none "$MECH" "$MODS" "$ENTS" "$ATTRS" "$RELS" "$MISMATCHES"
  exit 0
}

if [[ "$live" -eq 1 ]]; then
  printf '%s\n' '{"name":"live","tier":"live","shipped":"no","evidence":"--live"}' >"$MECH"
  refuse "live-connection-requested"
fi

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  refuse "not-a-git-repository"
fi

add_mech() {
  local name="$1" tier="$2" shipped="$3" evidence="$4"
  local esc_name esc_tier esc_shipped esc_ev
  esc_name="$(json_escape "$name")"
  esc_tier="$(json_escape "$tier")"
  esc_shipped="$(json_escape "$shipped")"
  esc_ev="$(json_escape "$evidence")"
  if ! grep -F -q "\"name\":\"$esc_name\"" "$MECH" 2>/dev/null; then
    printf '{"name":"%s","tier":"%s","shipped":"%s","evidence":"%s"}\n' \
      "$esc_name" "$esc_tier" "$esc_shipped" "$esc_ev" >>"$MECH"
  fi
}

module_of() {
  local rel="$1" first
  first="${rel%%/*}"
  if [[ "$first" == "$rel" ]]; then
    printf '.'
  else
    printf '%s' "$first"
  fi
}

entity_id() {
  local module="$1" name="$2"
  if [[ "$module" == "." ]]; then
    printf '%s' "$name"
  else
    printf '%s/%s' "$module" "$name"
  fi
}

# file lists
: >"$TMP/prisma.txt"
: >"$TMP/sql.txt"
: >"$TMP/cs.txt"
: >"$TMP/py.txt"
unshipped=""

while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  case "$rel" in
  data-model.json | data-model.md | data-model.dbml | */data-model.json | */data-model.md | */data-model.dbml)
    continue
    ;;
  *) ;;
  esac
  [[ -f "$repo/$rel" && ! -L "$repo/$rel" ]] || continue
  case "$rel" in
  *.prisma)
    printf '%s\n' "$rel" >>"$TMP/prisma.txt"
    ;;
  *.sql)
    case "$rel" in
    migrations/* | Migrations/* | */migrations/* | */Migrations/*)
      printf '%s\n' "$rel" >>"$TMP/sql.txt"
      ;;
    *) ;;
    esac
    ;;
  *.cs)
    printf '%s\n' "$rel" >>"$TMP/cs.txt"
    ;;
  *.py)
    printf '%s\n' "$rel" >>"$TMP/py.txt"
    ;;
  *) ;;
  esac
done < <(git -C "$repo" ls-files)

# Unshipped mechanisms. A hit refuses the whole record after mechanisms are listed.
scan_unshipped() {
  local rel line
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    [[ -f "$repo/$rel" && ! -L "$repo/$rel" ]] || continue
    if grep -E -q 'models\.Model' "$repo/$rel"; then
      add_mech django model no "$rel"
      unshipped="${unshipped} django"
    fi
    if grep -E -q 'sqlalchemy' "$repo/$rel" && grep -E -q 'mapped_column\(|Column\(' "$repo/$rel"; then
      add_mech sqlalchemy model no "$rel"
      unshipped="${unshipped} sqlalchemy"
    fi
  done <"$TMP/py.txt"
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    [[ -f "$repo/$rel" && ! -L "$repo/$rel" ]] || continue
    if grep -E -q '\[ForeignKey' "$repo/$rel"; then
      add_mech ef-annotation orm no "$rel"
      unshipped="${unshipped} ef-annotation"
    fi
  done <"$TMP/cs.txt"
}

scan_unshipped

if [[ -s "$TMP/prisma.txt" ]]; then
  first_prisma="$(head -n 1 "$TMP/prisma.txt")"
  add_mech prisma model yes "$first_prisma"
fi
if [[ -s "$TMP/sql.txt" ]]; then
  first_sql="$(head -n 1 "$TMP/sql.txt")"
  add_mech sql-migration migration yes "$first_sql"
fi

# --- Prisma -----------------------------------------------------------------
parse_prisma() {
  local rel="$1" module
  module="$(module_of "$rel")"
  awk -v module="$module" -v path="$rel" -v out_ents="$ENTS" -v out_attrs="$ATTRS" -v out_rels="$RELS" -v out_flag="$TMP/prisma-flag" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function base_type(t) {
      sub(/\?$/, "", t)
      sub(/\[\]$/, "", t)
      return t
    }
    function is_list(t) { return t ~ /\[\]$/ }
    function is_opt(t) { return t ~ /\?$/ || t ~ /\?\[\]$/ }
    function jesc(s) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\t/, "\\t", s)
      return s
    }
    function entity_id(mod, name) {
      if (mod == ".") return name
      return mod "/" name
    }
    function bracket_list(s, key,    i, rest, end) {
      i = index(s, key)
      if (i == 0) return ""
      rest = substr(s, i + length(key))
      i = index(rest, "[")
      if (i == 0) return ""
      rest = substr(rest, i + 1)
      end = index(rest, "]")
      if (end == 0) return ""
      rest = substr(rest, 1, end - 1)
      gsub(/[[:space:]]/, "", rest)
      return rest
    }
    BEGIN { nlines = 0; nmodels = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /\/\*/) { unsupported = 1 }
      nlines++
      lines[nlines] = line
      if (line ~ /^[ \t]*model[ \t]+[A-Za-z_]/) {
        tmp = line
        sub(/^[ \t]*model[ \t]+/, "", tmp)
        sub(/[^A-Za-z0-9_].*/, "", tmp)
        nmodels++
        models[nmodels] = tmp
        model_at[tmp] = 1
      }
    }
    END {
      if (unsupported) {
        printf "unsupported\n" > out_flag
        exit 0
      }
      inmodel = 0
      model = ""
      nf = 0
      for (li = 1; li <= nlines; li++) {
        line = lines[li]
        if (line ~ /^[ \t]*\/\//) continue
        if (line ~ /\/\//) {
          # cut a trailing comment that is not inside a string
          copy = line
          out = ""
          instr = 0
          for (ci = 1; ci <= length(copy); ci++) {
            c = substr(copy, ci, 1)
            if (c == "\"" && (ci == 1 || substr(copy, ci - 1, 1) != "\\")) instr = !instr
            if (!instr && c == "/" && substr(copy, ci + 1, 1) == "/") break
            out = out c
          }
          line = out
        }
        if (line ~ /^[ \t]*model[ \t]+[A-Za-z_]/) {
          tmp = line
          sub(/^[ \t]*model[ \t]+/, "", tmp)
          sub(/[^A-Za-z0-9_].*/, "", tmp)
          inmodel = 1
          model = tmp
          eid = entity_id(module, model)
          printf "{\"id\":\"%s\",\"name\":\"%s\",\"module\":\"%s\",\"evidence\":\"%s\"}\n", jesc(eid), jesc(model), jesc(module), jesc(path ":" li) >> out_ents
          continue
        }
        if (inmodel && line ~ /^[ \t]*\}/) { inmodel = 0; model = ""; continue }
        if (!inmodel) continue
        if (line ~ /^[ \t]*@@(unique|id)/) {
          set = bracket_list(line, (line ~ /^[ \t]*@@unique/ ? "@@unique" : "@@id"))
          gsub(/\([^)]*\)/, "", set)
          if (set != "") { nset[model]++; mset[model, nset[model]] = set }
        }
        if (line ~ /^[ \t]*@@/) continue
        stripped = trim(line)
        if (stripped == "" || substr(stripped, 1, 1) == "@") continue
        ntok = split(stripped, tok, /[ \t]+/)
        if (ntok < 2) continue
        fname = tok[1]
        ftype = tok[2]
        attrs = ""
        for (ti = 3; ti <= ntok; ti++) attrs = attrs tok[ti] " "
        nf++
        field_model[nf] = model
        field_name[nf] = fname
        field_type[nf] = ftype
        field_attrs[nf] = attrs
        field_line[nf] = li
        if (index(attrs, "@id") > 0 || index(attrs, " @id") > 0 || attrs ~ /(^|[^A-Za-z0-9_])@id([^A-Za-z0-9_]|$)/) field_pk[nf] = 1
        else field_pk[nf] = 0
        if (attrs ~ /(^|[^A-Za-z0-9_])@unique([^A-Za-z0-9_]|$)/) field_unique[nf] = 1
        else field_unique[nf] = 0
        field_opt[nf] = (is_opt(ftype) ? 1 : 0)
        field_list[nf] = (is_list(ftype) ? 1 : 0)
        field_base[nf] = base_type(ftype)
        if (index(attrs, "fields:") > 0) field_has_fields[nf] = 1
        else field_has_fields[nf] = 0
      }
      # implicit many-to-many: mutual list fields and no fields: side
      for (i = 1; i <= nf; i++) {
        if (!field_list[i]) continue
        if (!(field_base[i] in model_at)) continue
        for (j = 1; j <= nf; j++) {
          if (field_model[j] != field_base[i]) continue
          if (!field_list[j]) continue
          if (field_base[j] != field_model[i]) continue
          if (field_has_fields[i] || field_has_fields[j]) continue
          # a fields: relation elsewhere between these models is a normal 1-n plus an extra list
          has_fk = 0
          for (k = 1; k <= nf; k++) {
            if (!field_has_fields[k]) continue
            if ((field_model[k] == field_model[i] && field_base[k] == field_model[j]) || (field_model[k] == field_model[j] && field_base[k] == field_model[i]))
              has_fk = 1
          }
          if (!has_fk) implicit = 1
        }
      }
      if (implicit) {
        printf "implicit-many-to-many\n" > out_flag
        exit 0
      }
      for (i = 1; i <= nf; i++) {
        model = field_model[i]
        base = field_base[i]
        is_rel = (base in model_at)
        if (is_rel) continue
        nullable = (field_opt[i] ? "yes" : "no")
        pk = (field_pk[i] ? "yes" : "no")
        eid = entity_id(module, model)
        printf "{\"entity\":\"%s\",\"name\":\"%s\",\"type\":\"%s\",\"nullable\":\"%s\",\"pk\":\"%s\",\"fk\":\"no\",\"evidence\":\"%s\"}\n", \
          jesc(eid), jesc(field_name[i]), jesc(base), nullable, pk, jesc(path ":" field_line[i]) >> out_attrs
        scalar_opt[model SUBSEP field_name[i]] = field_opt[i]
        scalar_unique[model SUBSEP field_name[i]] = field_unique[i]
        scalar_pk[model SUBSEP field_name[i]] = field_pk[i]
      }
      for (i = 1; i <= nf; i++) {
        if (!field_has_fields[i]) continue
        if (!(field_base[i] in model_at)) {
          printf "unresolved-target\n" > out_flag
          exit 0
        }
        cols = bracket_list(field_attrs[i], "fields:")
        if (cols == "") {
          printf "unreadable-relation\n" > out_flag
          exit 0
        }
        refs = bracket_list(field_attrs[i], "references:")
        nsplit = split(cols, col, ",")
        any_opt = field_opt[i]
        disagree = 0
        for (c = 1; c <= nsplit; c++) {
          key = field_model[i] SUBSEP col[c]
          fkset[col[c]] = 1
          if (key in scalar_opt) {
            if (scalar_opt[key] != field_opt[i]) disagree = 1
            if (scalar_opt[key]) any_opt = 1
          }
        }
        if (disagree) {
          printf "optionality-disagrees\n" > out_flag
          exit 0
        }
        # unique when an @id, an @unique, or a @@unique/@@id column set lies inside the foreign-key columns
        uniq = 0
        for (c = 1; c <= nsplit; c++) {
          key = field_model[i] SUBSEP col[c]
          if (scalar_unique[key] == 1 || scalar_pk[key] == 1) uniq = 1
        }
        for (m = 1; m <= nset[field_model[i]] && !uniq; m++) {
          nmc = split(mset[field_model[i], m], mc, ",")
          inside = 1
          for (c = 1; c <= nmc; c++) if (!(mc[c] in fkset)) inside = 0
          if (inside) uniq = 1
        }
        for (c = 1; c <= nsplit; c++) delete fkset[col[c]]
        if (!uniq && nsplit > 1) {
          printf "unknown-cardinality\n" > out_flag
          exit 0
        }
        kind = (uniq ? "one-to-one" : "one-to-many")
        if (uniq) token = (any_opt ? "|o--o|" : "||--o|")
        else token = (any_opt ? "|o--o{" : "||--o{")
        opt = (any_opt ? "yes" : "no")
        from = entity_id(module, field_model[i])
        to = entity_id(module, field_base[i])
        printf "{\"from\":\"%s\",\"to\":\"%s\",\"cardinality\":\"%s\",\"columns\":\"%s\",\"references\":\"%s\",\"optional\":\"%s\",\"kind\":\"%s\",\"evidence\":\"%s\",\"tool\":\"prisma\"}\n", \
          jesc(from), jesc(to), token, jesc(cols), jesc(refs), opt, kind, jesc(path ":" field_line[i]) >> out_rels
        for (c = 1; c <= nsplit; c++) fk_col[from SUBSEP col[c]] = 1
      }
    }
  ' "$repo/$rel"
}

prisma_flag=""
if [[ -s "$TMP/prisma.txt" ]]; then
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    : >"$TMP/prisma-flag"
    parse_prisma "$rel"
    if [[ -s "$TMP/prisma-flag" ]]; then
      prisma_flag="$(head -n 1 "$TMP/prisma-flag")"
      break
    fi
  done <"$TMP/prisma.txt"
fi


SQL_ENTS="$TMP/sql-entities.tsv"
SQL_ATTRS="$TMP/sql-attributes.tsv"
SQL_RELS="$TMP/sql-relationships.tsv"
sql_bad=0
if [[ -s "$TMP/sql.txt" ]]; then
  : >"$TMP/sql-replay.sql"
  : >"$SQL_ENTS"
  : >"$SQL_ATTRS"
  : >"$SQL_RELS"
  : >"$TMP/sql-flag"
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    {
      printf '%s\n' "-- MAPDATA FILE $rel"
      cat "$repo/$rel"
      printf '\n'
    } >>"$TMP/sql-replay.sql"
  done < <(sort "$TMP/sql.txt")
  # One replay across every migration file. The sentinel carries the path so
  # evidence and module follow the file that declared the row. Readable
  # statements: CREATE TABLE (inline and table-level FOREIGN KEY, UNIQUE and
  # PRIMARY KEY), CREATE UNIQUE INDEX, DROP INDEX, DROP TABLE, and ALTER TABLE
  # ADD COLUMN, DROP COLUMN, DROP CONSTRAINT of a constraint this replay
  # recorded, ADD [CONSTRAINT n] FOREIGN KEY, UNIQUE and PRIMARY KEY. Any other
  # ALTER TABLE action sets the flag and the tier is not used.
  awk -v ents="$SQL_ENTS" -v attrs="$SQL_ATTRS" -v rels="$SQL_RELS" -v flag="$TMP/sql-flag" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function stripq(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (substr(s, 1, 1) == "\"") { sub(/^"/, "", s); sub(/"$/, "", s) }
      if (substr(s, 1, 1) == "`") { sub(/^`/, "", s); sub(/`$/, "", s) }
      if (substr(s, 1, 1) == "[") { sub(/^\[/, "", s); sub(/\]$/, "", s) }
      return s
    }
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function entity_id(mod, name) {
      if (mod == ".") return name
      return mod "/" name
    }
    function module_of(rel,    first) {
      first = rel
      sub(/\/.*/, "", first)
      if (first == rel) return "."
      return first
    }
    function joined_cols(s,    n, k, parts, out) {
      gsub(/[[:space:]]/, "", s)
      n = split(s, parts, ",")
      out = ""
      for (k = 1; k <= n; k++) out = out (k > 1 ? "," : "") stripq(parts[k])
      return out
    }
    function has_col(list, col) { return index("," list ",", "," col ",") > 0 }
    function con_name(s,    t) {
      if (!match(s, /^([Aa][Dd][Dd][ \t]+)?[Cc][Oo][Nn][Ss][Tt][Rr][Aa][Ii][Nn][Tt][ \t]+[^ \t]+/)) return ""
      t = substr(s, RSTART, RLENGTH)
      sub(/^.*[ \t]/, "", t)
      return stripq(t)
    }
    function add_uniq(tab, cols, name) {
      if (cols == "" || cols ~ /[()]/) return
      nuq[tab]++
      uq[tab, nuq[tab]] = cols
      uqname[tab, nuq[tab]] = name
    }
    function forget(name,    eid, i) {
      eid = entity_id(module, name)
      for (i = 1; i <= nent; i++) if (ent_id[i] == eid) ent_dead[i] = 1
      for (i = 1; i <= nattr; i++) if (attr_entity[i] == eid) attr_dead[i] = 1
      for (i = 1; i <= nrel; i++) if (rel_from[i] == eid || rel_to[i] == eid) rel_dead[i] = 1
    }
    function add_rel(tab, cols, rest, cname,    nm, refcols, n, c, parts, any_opt) {
      rest = trim(rest)
      nm = rest
      sub(/[ \t]*\(.*/, "", nm)
      sub(/[ \t,;].*/, "", nm)
      refcols = ""
      if (rest ~ /^[^ \t(,;]+[ \t]*\(/) {
        refcols = rest
        sub(/^[^(]*\(/, "", refcols)
        sub(/\).*/, "", refcols)
        refcols = joined_cols(refcols)
      }
      n = split(cols, parts, ",")
      any_opt = 0
      for (c = 1; c <= n; c++) if ((tab SUBSEP parts[c]) in nulls && nulls[tab SUBSEP parts[c]] == 1) any_opt = 1
      nrel++
      rel_from[nrel] = entity_id(module, tab)
      rel_to[nrel] = entity_id(module, stripq(nm))
      rel_dead[nrel] = 0
      rel_tab[nrel] = tab
      rel_cols[nrel] = cols
      rel_refs[nrel] = refcols
      rel_opt[nrel] = any_opt
      rel_ev[nrel] = path ":" sline
      rel_name[nrel] = cname
    }
    function add_fk(tab, text, cname,    tmp, cols, rest) {
      tmp = text
      sub(/.*[Ff][Oo][Rr][Ee][Ii][Gg][Nn][ \t]+[Kk][Ee][Yy][ \t]*/, "", tmp)
      sub(/^[ \t]*\(/, "", tmp)
      cols = tmp
      sub(/\).*/, "", cols)
      rest = tmp
      sub(/^[^)]*\)/, "", rest)
      if (!match(rest, /[Rr][Ee][Ff][Ee][Rr][Ee][Nn][Cc][Ee][Ss][ \t]+/)) { bad = 1; return }
      add_rel(tab, joined_cols(cols), substr(rest, RSTART + RLENGTH), cname)
    }
    function column_def(tab, def,    stripped, tok, ntok, cname, ctype, spec, k, nullable, pk, up) {
      stripped = trim(def)
      sub(/,$/, "", stripped)
      if (stripped == "" || stripped ~ /^\(/) return
      ntok = split(stripped, tok, /[ \t]+/)
      if (ntok < 2) return
      cname = stripq(tok[1])
      if (toupper(cname) == "CONSTRAINT") return
      ctype = tok[2]
      sub(/,$/, "", ctype)
      spec = ""
      for (k = 3; k <= ntok; k++) spec = spec (k > 3 ? " " : "") tok[k]
      up = toupper(spec)
      nullable = (up ~ /NOT[ \t]+NULL/ ? "no" : "yes")
      pk = "no"
      if (up ~ /PRIMARY[ \t]+KEY/) { pk = "yes"; nullable = "no"; add_uniq(tab, cname, "") }
      if (up ~ /(^|[^A-Z0-9_])UNIQUE([^A-Z0-9_]|$)/) add_uniq(tab, cname, "")
      nulls[tab SUBSEP cname] = (nullable == "yes" ? 1 : 0)
      nattr++
      attr_entity[nattr] = entity_id(module, tab)
      attr_name[nattr] = cname
      attr_dead[nattr] = 0
      attr_line[nattr] = sprintf("{\"entity\":\"%s\",\"name\":\"%s\",\"type\":\"%s\",\"nullable\":\"%s\",\"pk\":\"%s\",\"fk\":\"no\",\"evidence\":\"%s\"}", jesc(entity_id(module, tab)), jesc(cname), jesc(ctype), nullable, pk, jesc(path ":" sline))
      if (match(spec, /(^|[ \t])[Rr][Ee][Ff][Ee][Rr][Ee][Nn][Cc][Ee][Ss][ \t]+/)) add_rel(tab, cname, substr(spec, RSTART + RLENGTH), "")
    }
    function table_item(tab, item,    iu, tmp) {
      iu = toupper(item)
      if (iu ~ /FOREIGN[ \t]+KEY/) { add_fk(tab, item, con_name(trim(item))); return }
      if (iu ~ /^[ \t]*(CONSTRAINT[ \t]+[^ \t]+[ \t]+)?(UNIQUE|PRIMARY[ \t]+KEY)[ \t]*\(/ || iu ~ /^[ \t]*UNIQUE[ \t]+(INDEX|KEY)[ \t]/) {
        tmp = item
        sub(/^[^(]*\(/, "", tmp)
        sub(/\).*/, "", tmp)
        add_uniq(tab, joined_cols(tmp), con_name(trim(item)))
        return
      }
      if (iu ~ /^[ \t]*(CONSTRAINT|PRIMARY|CHECK|INDEX|KEY|FULLTEXT|SPATIAL)[ \t]/) return
      column_def(tab, item)
    }
    function drop_column(tab, col,    eid, i, m) {
      eid = entity_id(module, tab)
      for (i = 1; i <= nattr; i++) if (attr_entity[i] == eid && attr_name[i] == col) attr_dead[i] = 1
      for (i = 1; i <= nrel; i++) {
        if (rel_tab[i] == tab && has_col(rel_cols[i], col)) rel_dead[i] = 1
        if (rel_to[i] == eid && has_col(rel_refs[i], col)) rel_dead[i] = 1
      }
      for (m = 1; m <= nuq[tab]; m++) if (has_col(uq[tab, m], col)) uq[tab, m] = ""
      delete nulls[tab SUBSEP col]
    }
    function drop_constraint(tab, name,    i, m, hit) {
      hit = 0
      if (name == "") { bad = 1; return }
      for (i = 1; i <= nrel; i++) if (!rel_dead[i] && rel_tab[i] == tab && rel_name[i] == name) { rel_dead[i] = 1; hit = 1 }
      for (m = 1; m <= nuq[tab]; m++) if (uq[tab, m] != "" && uqname[tab, m] == name) { uq[tab, m] = ""; hit = 1 }
      if (!hit) bad = 1
    }
    function drop_index(name,    t, m) {
      if (name == "") return
      for (t in nuq) for (m = 1; m <= nuq[t]; m++) if (uq[t, m] != "" && uqname[t, m] == name) uq[t, m] = ""
    }
    function close_pos(s,    i, c, depth, instr) {
      depth = 1; instr = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (instr != "") { if (c == instr) instr = "" }
        else if (c == "'\''" || c == "\"" || c == "`") instr = c
        else if (c == "(") depth++
        else if (c == ")") { depth--; if (depth == 0) return i }
      }
      return 0
    }
    function split_actions(s,    n, i, c, depth, instr, cur_a) {
      n = 0; depth = 0; instr = ""; cur_a = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (instr != "") { if (c == instr) instr = "" }
        else if (c == "'\''" || c == "\"" || c == "`") instr = c
        else if (c == "(") depth++
        else if (c == ")") depth--
        else if (c == "," && depth == 0) { acts[++n] = cur_a; cur_a = ""; continue }
        cur_a = cur_a c
      }
      acts[++n] = cur_a
      return n
    }
    function alter_stmt(s,    tmp, tab, rest, n, i, a, au, name) {
      tmp = s
      sub(/^[ \t]*[Aa][Ll][Tt][Ee][Rr][ \t]+[Tt][Aa][Bb][Ll][Ee][ \t]+/, "", tmp)
      sub(/^[Ii][Ff][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", tmp)
      sub(/^[Oo][Nn][Ll][Yy][ \t]+/, "", tmp)
      tab = tmp
      sub(/[ \t].*/, "", tab)
      rest = substr(tmp, length(tab) + 1)
      sub(/[ \t]*;.*/, "", rest)
      tab = stripq(tab)
      n = split_actions(rest)
      for (i = 1; i <= n; i++) {
        a = trim(acts[i])
        au = toupper(a)
        if (au ~ /^ADD[ \t]+(CONSTRAINT[ \t]+[^ \t]+[ \t]+)?(UNIQUE|PRIMARY[ \t]+KEY)[ \t]*\(/) {
          tmp = a
          sub(/^[^(]*\(/, "", tmp)
          sub(/\).*/, "", tmp)
          add_uniq(tab, joined_cols(tmp), con_name(a))
        } else if (au ~ /^ADD[ \t]+(CONSTRAINT[ \t]+[^ \t]+[ \t]+)?FOREIGN[ \t]+KEY[ \t]*\(/) {
          add_fk(tab, a, con_name(a))
        } else if (au ~ /^ADD[ \t]+COLUMN[ \t]/) {
          tmp = a
          sub(/^[Aa][Dd][Dd][ \t]+[Cc][Oo][Ll][Uu][Mm][Nn][ \t]+/, "", tmp)
          sub(/^[Ii][Ff][ \t]+[Nn][Oo][Tt][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", tmp)
          column_def(tab, tmp)
        } else if (au ~ /^DROP[ \t]+COLUMN[ \t]/) {
          tmp = a
          sub(/^[Dd][Rr][Oo][Pp][ \t]+[Cc][Oo][Ll][Uu][Mm][Nn][ \t]+/, "", tmp)
          sub(/^[Ii][Ff][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", tmp)
          sub(/[ \t].*/, "", tmp)
          drop_column(tab, stripq(tmp))
        } else if (au ~ /^DROP[ \t]+CONSTRAINT[ \t]/) {
          tmp = a
          sub(/^[Dd][Rr][Oo][Pp][ \t]+[Cc][Oo][Nn][Ss][Tt][Rr][Aa][Ii][Nn][Tt][ \t]+/, "", tmp)
          sub(/^[Ii][Ff][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", tmp)
          sub(/[ \t].*/, "", tmp)
          drop_constraint(tab, stripq(tmp))
        } else bad = 1
      }
    }
    function flush_alt() {
      if (!alt) return
      sline = alt_line
      alter_stmt(stmt)
      alt = 0
      stmt = ""
    }
    BEGIN { path = ""; module = "."; inn = 0; fline = 0; alt = 0; bad = 0 }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw ~ /^-- MAPDATA FILE /) {
        flush_alt()
        path = substr(raw, 17)
        module = module_of(path)
        inn = 0
        fline = 0
        next
      }
      fline++
      sline = fline
      line = raw
      if (line ~ /--/) {
        out = ""; instr = 0
        for (ci = 1; ci <= length(line); ci++) {
          c = substr(line, ci, 1)
          if (c == "'\''") instr = !instr
          if (!instr && c == "-" && substr(line, ci + 1, 1) == "-") break
          out = out c
        }
        line = out
      }
      if (alt) {
        stmt = stmt " " line
        if (line ~ /;/) flush_alt()
        next
      }
      up = toupper(line)
      if (!inn && up ~ /^[ \t]*DROP[ \t]+TABLE[ \t]/) {
        tmp = line
        sub(/.*[Tt][Aa][Bb][Ll][Ee][ \t]+/, "", tmp)
        sub(/[ \t]*;.*/, "", tmp)
        sub(/^[Ii][Ff][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", tmp)
        tmp = stripq(trim(tmp))
        sub(/[ \t].*/, "", tmp)
        forget(tmp)
        next
      }
      if (!inn && up ~ /^[ \t]*CREATE[ \t]+TABLE[ \t]/) {
        tmp = line
        sub(/.*[Tt][Aa][Bb][Ll][Ee][ \t]+/, "", tmp)
        sub(/^[Ii][Ff][ \t]+[Nn][Oo][Tt][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", tmp)
        tmp = trim(tmp)
        sub(/[ \t]*\(.*/, "", tmp)
        tname = stripq(tmp)
        sub(/[ \t].*/, "", tname)
        forget(tname)
        nuq[tname] = 0
        inn = 1
        cur = tname
        eid = entity_id(module, cur)
        nent++
        ent_id[nent] = eid
        ent_dead[nent] = 0
        ent_line[nent] = sprintf("{\"id\":\"%s\",\"name\":\"%s\",\"module\":\"%s\",\"evidence\":\"%s\"}", jesc(eid), jesc(cur), jesc(module), jesc(path ":" fline))
        # items on the CREATE TABLE line itself, up to the closing parenthesis when it is there
        body = line
        if (sub(/^[^(]*\(/, "", body)) {
          closed = close_pos(body)
          if (closed > 0) body = substr(body, 1, closed - 1)
          if (trim(body) != "") {
            nn = split_actions(body)
            for (k = 1; k <= nn; k++) table_item(cur, acts[k])
          }
          if (closed > 0) { inn = 0; cur = "" }
        }
        next
      }
      if (!inn && up ~ /^[ \t]*CREATE[ \t]+UNIQUE[ \t]+INDEX[ \t]/ && up !~ /[ \t]WHERE[ \t]/ && (p = index(up, " ON ")) > 0) {
        iname = line
        sub(/^[ \t]*[Cc][Rr][Ee][Aa][Tt][Ee][ \t]+[Uu][Nn][Ii][Qq][Uu][Ee][ \t]+[Ii][Nn][Dd][Ee][Xx][ \t]+/, "", iname)
        sub(/^[Cc][Oo][Nn][Cc][Uu][Rr][Rr][Ee][Nn][Tt][Ll][Yy][ \t]+/, "", iname)
        sub(/^[Ii][Ff][ \t]+[Nn][Oo][Tt][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", iname)
        sub(/[ \t(].*/, "", iname)
        tmp = substr(line, p + 4)
        sub(/^[ \t]*[Oo][Nn][Ll][Yy][ \t]+/, "", tmp)
        itab = tmp
        sub(/[ \t]*(\(|[Uu][Ss][Ii][Nn][Gg][ \t]).*/, "", itab)
        sub(/^[^(]*\(/, "", tmp)
        sub(/\).*/, "", tmp)
        add_uniq(stripq(itab), joined_cols(tmp), stripq(iname))
        next
      }
      if (!inn && up ~ /^[ \t]*DROP[ \t]+INDEX[ \t]/) {
        tmp = line
        sub(/^[ \t]*[Dd][Rr][Oo][Pp][ \t]+[Ii][Nn][Dd][Ee][Xx][ \t]+/, "", tmp)
        sub(/^[Cc][Oo][Nn][Cc][Uu][Rr][Rr][Ee][Nn][Tt][Ll][Yy][ \t]+/, "", tmp)
        sub(/^[Ii][Ff][ \t]+[Ee][Xx][Ii][Ss][Tt][Ss][ \t]+/, "", tmp)
        sub(/[ \t]*;.*/, "", tmp)
        sub(/[ \t]+[Oo][Nn][ \t].*/, "", tmp)
        nn = split(tmp, parts, ",")
        for (k = 1; k <= nn; k++) drop_index(stripq(parts[k]))
        next
      }
      if (!inn && up ~ /^[ \t]*ALTER[ \t]+TABLE[ \t]/) {
        alt = 1
        stmt = line
        alt_line = fline
        if (line ~ /;/) flush_alt()
        next
      }
      if (inn && up ~ /^[ \t]*\)/) { inn = 0; cur = ""; next }
      if (!inn) next
      table_item(cur, line)
    }
    END {
      flush_alt()
      if (bad) print "sql-alter-unreadable" > flag
      for (i = 1; i <= nent; i++) if (!ent_dead[i]) print ent_line[i] >> ents
      for (i = 1; i <= nattr; i++) if (!attr_dead[i]) print attr_line[i] >> attrs
      for (i = 1; i <= nrel; i++) {
        if (rel_dead[i]) continue
        # unique when a declared unique or primary-key column set lies inside the foreign-key columns
        nsplit = split(rel_cols[i], col, ",")
        for (c = 1; c <= nsplit; c++) fkset[col[c]] = 1
        uniq = 0
        for (m = 1; m <= nuq[rel_tab[i]] && !uniq; m++) {
          if (uq[rel_tab[i], m] == "") continue
          nmc = split(uq[rel_tab[i], m], mc, ",")
          inside = 1
          for (c = 1; c <= nmc; c++) if (!(mc[c] in fkset)) inside = 0
          if (inside) uniq = 1
        }
        for (c = 1; c <= nsplit; c++) delete fkset[col[c]]
        if (uniq) { kind = "one-to-one"; token = (rel_opt[i] ? "|o--o|" : "||--o|") }
        else if (nsplit > 1) { kind = "unknown"; token = "unknown" }
        else { kind = "one-to-many"; token = (rel_opt[i] ? "|o--o{" : "||--o{") }
        printf "{\"from\":\"%s\",\"to\":\"%s\",\"cardinality\":\"%s\",\"columns\":\"%s\",\"references\":\"%s\",\"optional\":\"%s\",\"kind\":\"%s\",\"evidence\":\"%s\",\"tool\":\"sql-migration\"}\n", \
          jesc(rel_from[i]), jesc(rel_to[i]), token, jesc(rel_cols[i]), jesc(rel_refs[i]), (rel_opt[i] ? "yes" : "no"), kind, jesc(rel_ev[i]) >> rels
      }
    }
  ' "$TMP/sql-replay.sql"
  if [[ -s "$TMP/sql-flag" ]]; then
    sql_bad=1
  fi
fi

# --- EF fluent --------------------------------------------------------------
ef_seen=0
ef_bad=0
ef_why=""
ef_evidence=""
EF_ENTS="$TMP/ef-entities.tsv"
EF_ATTRS="$TMP/ef-attributes.tsv"
EF_RELS="$TMP/ef-relationships.tsv"
EF_DECLS="$TMP/ef-declarations.tsv"
: >"$EF_ENTS"
: >"$EF_ATTRS"
: >"$EF_RELS"
ef_id='[A-Za-z_][A-Za-z0-9_]*'
ef_decls_ready=0
EF_MEMBER=""
EF_NAV=""
EF_OPT=""
cfg_entity=""
cfg_builder=""

# One awk pass over the tracked .cs files, one row per property declared in a
# class body: module, class, property, declared type (tab separated). Braces set
# the enclosing class; a property is the header before a "{" that has a type, a
# name and no "(" or "=". Anything else (fields, methods, positional record
# members) has no row, so a lookup that needs it finds nothing and the chain refuses.
ef_load_decls() {
  [[ "$ef_decls_ready" -eq 0 ]] || return 0
  ef_decls_ready=1
  : >"$EF_DECLS"
  # shellcheck disable=SC2016 # the awk program is literal; xargs hides it from shellcheck's awk rule
  sed 's:^:./:' "$TMP/cs.txt" | tr '\n' '\0' | (cd "$repo" && xargs -0 awk '
    function open_block(   h, nw, w, i, name, ty) {
      h = buf
      buf = ""
      gsub(/\[[A-Za-z][^]]*\]/, " ", h)
      depth++
      if (match(h, /(^|[ \t])(class|struct|record|interface)[ \t]+((class|struct)[ \t]+)?[A-Za-z_][A-Za-z0-9_]*/)) {
        nw = split(substr(h, RSTART, RLENGTH), w, " ")
        cls[depth] = w[nw]
        return
      }
      if (!((depth - 1) in cls)) return
      if (h ~ /[^A-Za-z0-9_<>?,. \t]/) return
      nw = split(h, w, " ")
      name = w[nw]
      if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) return
      i = 1
      while (i < nw && (w[i] in mod)) i++
      if (i >= nw || w[i] == "enum" || w[i] == "event") return
      ty = ""
      for (; i < nw; i++) ty = ty w[i]
      print module "\t" cls[depth - 1] "\t" name "\t" ty
    }
    BEGIN {
      n = split("public private protected internal virtual override new static readonly required abstract sealed unsafe partial extern volatile", m, " ")
      for (i = 1; i <= n; i++) mod[m[i]] = 1
    }
    FNR == 1 {
      for (k in cls) delete cls[k]
      depth = 0
      buf = ""
      f = FILENAME
      sub(/^\.\//, "", f)
      module = index(f, "/") ? substr(f, 1, index(f, "/") - 1) : "."
    }
    /^[ \t]*#/ { next }
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/\/\/.*$/, "", line)
      while (line != "") {
        if (!match(line, /[{};]/)) { buf = buf " " line; break }
        buf = buf " " substr(line, 1, RSTART - 1)
        d = substr(line, RSTART, 1)
        line = substr(line, RSTART + 1)
        if (d == "{") open_block()
        else if (d == "}") { delete cls[depth]; if (depth > 0) depth--; buf = "" }
        else buf = ""
      }
    }
  ' >>"$EF_DECLS")
}

# ef_decl_type <module> <class> <property>: the declared type when the class
# declares that property with exactly one type, preferring the module's own
# declarations over the rest of the repository; nothing otherwise.
ef_decl_type() {
  EF_M="$1" EF_C="$2" EF_P="$3" awk -F'\t' '
    $2 == ENVIRON["EF_C"] && $3 == ENVIRON["EF_P"] { any[$4] = 1; if ($1 == ENVIRON["EF_M"]) here[$4] = 1 }
    END {
      for (t in here) { n++; ty = t }
      if (n == 0) for (t in any) { n++; ty = t }
      if (n == 1) print ty
    }
  ' "$EF_DECLS"
}

# ef_lambda_member <call> <text>: sets EF_MEMBER to P when the text holds
# call(x => x.P) with the same variable on both sides; fails otherwise.
ef_lambda_member() {
  local re="$1"'[[:space:]]*\([[:space:]]*\(?('"$ef_id"')\)?[[:space:]]*=>[[:space:]]*('"$ef_id"')\.('"$ef_id"')[[:space:]]*\)'
  EF_MEMBER=""
  [[ "$2" =~ $re ]] && [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]] && EF_MEMBER="${BASH_REMATCH[3]}"
  [[ -n "$EF_MEMBER" ]]
}

# ef_nav_target <module> <class> <property> <collection|reference>: sets EF_NAV
# to the entity a navigation property points at, from its declared type.
ef_nav_target() {
  local ty re
  ef_load_decls
  EF_NAV=""
  ty="$(ef_decl_type "$1" "$2" "$3")"
  ty="${ty%\?}"
  if [[ "$4" == collection ]]; then
    re='^(ICollection|List|IList|IEnumerable|HashSet)<('"$ef_id"')>$'
    [[ "$ty" =~ $re ]] && EF_NAV="${BASH_REMATCH[2]}"
  else
    re='^('"$ef_id"')$'
    [[ "$ty" =~ $re ]] && EF_NAV="${BASH_REMATCH[1]}"
  fi
  [[ -n "$EF_NAV" ]]
}

# ef_optional <module> <class> <property>: sets EF_OPT from a foreign-key
# property's declared type, as EF Core does: nullable is optional, a non-nullable
# value type is required. A type whose nullability depends on the project
# (plain string, an enum) or a property that is not declared fails.
ef_optional() {
  local ty
  ef_load_decls
  ty="$(ef_decl_type "$1" "$2" "$3")"
  case "$ty" in
  *"?" | "Nullable<"* | "System.Nullable<"*) EF_OPT=yes ;;
  int | uint | long | ulong | short | ushort | byte | sbyte | Guid | System.Guid | DateTime | DateTimeOffset) EF_OPT=no ;;
  *) return 1 ;;
  esac
}

# ef_config_class <flattened source>: sets cfg_entity and cfg_builder when the
# file declares exactly one IEntityTypeConfiguration<T> class whose Configure
# takes an EntityTypeBuilder<T> parameter; both empty otherwise.
ef_config_class() {
  local needle='IEntityTypeConfiguration<' rest re
  cfg_entity=""
  cfg_builder=""
  rest="${1//"$needle"/}"
  [[ $((${#1} - ${#rest})) -eq ${#needle} ]] || return 0
  re='class[[:space:]]+'"$ef_id"'[^{;]*IEntityTypeConfiguration<('"$ef_id"')>'
  [[ "$1" =~ $re ]] || return 0
  cfg_entity="${BASH_REMATCH[1]}"
  re='Configure[[:space:]]*\([[:space:]]*EntityTypeBuilder<'"$cfg_entity"'>[[:space:]]+('"$ef_id"')[[:space:]]*\)'
  if [[ "$1" =~ $re ]]; then
    cfg_builder="${BASH_REMATCH[1]}"
  else
    cfg_entity=""
  fi
  return 0
}

set -f
while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  [[ -f "$repo/$rel" && ! -L "$repo/$rel" ]] || continue
  if ! grep -E -q 'Has(One|Many|ForeignKey)' "$repo/$rel"; then
    continue
  fi
  ef_seen=1
  ef_evidence="$rel"
  module="$(module_of "$rel")"
  flattened="$(sed -E 's://.*$::' "$repo/$rel" | tr '\n' ' ')"
  ef_config_class "$flattened"
  IFS=';' read -r -a statements <<<"$flattened"
  for part in "${statements[@]}"; do
    [[ "$part" == *HasOne* || "$part" == *HasMany* || "$part" == *HasForeignKey* ]] || continue
    configured="" one="" many="" one_nav="" many_nav="" fk="" principal=""
    if [[ "$part" == *HasPrincipalKey* ]]; then
      [[ "$part" =~ HasPrincipalKey\(\"([A-Za-z_][A-Za-z0-9_]*)\"\) ]] && principal="${BASH_REMATCH[1]}"
      if [[ -z "$principal" ]] && ef_lambda_member HasPrincipalKey "$part"; then principal="$EF_MEMBER"; fi
      if [[ -z "$principal" ]]; then
        ef_bad=1
        break
      fi
    fi
    [[ "$part" =~ Entity\<([A-Za-z_][A-Za-z0-9_]*)\> ]] && configured="${BASH_REMATCH[1]}" # portability-ok: C# generic type argument, not a GNU \< \> word boundary
    if [[ -z "$configured" && -n "$cfg_builder" ]]; then
      root="${part%%Has[OM]*}"
      re='(^|[^A-Za-z0-9_.])'"$cfg_builder"'[[:space:]]*\.[[:space:]]*$'
      [[ "$root" =~ $re ]] && configured="$cfg_entity"
    fi
    [[ "$part" =~ HasOne\<([A-Za-z_][A-Za-z0-9_]*)\> ]] && one="${BASH_REMATCH[1]}" # portability-ok: C# generic type argument, not a GNU \< \> word boundary
    [[ "$part" =~ HasMany\<([A-Za-z_][A-Za-z0-9_]*)\> ]] && many="${BASH_REMATCH[1]}" # portability-ok: C# generic type argument, not a GNU \< \> word boundary
    [[ "$part" =~ HasForeignKey\(\"([A-Za-z_][A-Za-z0-9_]*)\"\) ]] && fk="${BASH_REMATCH[1]}"
    if [[ -z "$fk" ]] && ef_lambda_member HasForeignKey "$part"; then fk="$EF_MEMBER"; fi
    if [[ -z "$configured" || -z "$fk" ]]; then
      ef_bad=1
      break
    fi
    if [[ -z "$one" ]] && ef_lambda_member HasOne "$part"; then one_nav="$EF_MEMBER"; fi
    if [[ -z "$many" ]] && ef_lambda_member HasMany "$part"; then many_nav="$EF_MEMBER"; fi
    if [[ -n "$one_nav" ]]; then
      if ! ef_nav_target "$module" "$configured" "$one_nav" reference; then
        ef_bad=1
        ef_why="$configured.$one_nav is not declared as a reference to one entity type"
        break
      fi
      one="$EF_NAV"
    fi
    if [[ -n "$many_nav" ]]; then
      if ! ef_nav_target "$module" "$configured" "$many_nav" collection; then
        ef_bad=1
        ef_why="$configured.$many_nav is not declared as a collection of one entity type"
        break
      fi
      many="$EF_NAV"
    fi
    if [[ -n "$one" && -n "$many" ]]; then
      ef_bad=1
      break
    fi
    kind="" fk_entity="" pk_entity=""
    if [[ -n "$one" && "$part" == *WithMany* ]]; then
      fk_entity="$configured"
      pk_entity="$one"
      kind="one-to-many"
    elif [[ -n "$many" && "$part" == *WithOne* ]]; then
      fk_entity="$many"
      pk_entity="$configured"
      kind="one-to-many"
    elif [[ -n "$one" && -z "$one_nav" && "$part" == *WithOne* ]]; then
      fk_entity="$configured"
      pk_entity="$one"
      kind="one-to-one"
    else
      ef_bad=1
      break
    fi
    optional=""
    if [[ "$part" =~ IsRequired\(false\) ]]; then
      optional="yes"
    elif [[ "$part" =~ IsRequired\((true)?\) ]]; then
      optional="no"
    elif [[ "$part" == *IsRequired* ]]; then
      ef_bad=1
      ef_why="IsRequired takes an argument other than true or false"
      break
    elif ef_optional "$module" "$fk_entity" "$fk"; then
      optional="$EF_OPT"
    else
      ef_bad=1
      ef_why="$fk_entity.$fk has no declared type that settles whether it is nullable"
      break
    fi
    if [[ "$kind" == "one-to-one" ]]; then
      token="$([[ "$optional" == "yes" ]] && printf '|o--o|' || printf '||--o|')"
    else
      token="$([[ "$optional" == "yes" ]] && printf '|o--o{' || printf '||--o{')"
    fi
    from="$(entity_id "$module" "$fk_entity")"
    to="$(entity_id "$module" "$pk_entity")"
    # entities (once)
    for pair in "$fk_entity" "$pk_entity"; do
      eid="$(entity_id "$module" "$pair")"
      esc_id="$(json_escape "$eid")"
      if ! grep -F -q "\"id\":\"$esc_id\"" "$EF_ENTS"; then
        printf '{"id":"%s","name":"%s","module":"%s","evidence":"%s"}\n' \
          "$esc_id" "$(json_escape "$pair")" "$(json_escape "$module")" "$(json_escape "$rel")" >>"$EF_ENTS"
      fi
    done
    printf '{"from":"%s","to":"%s","cardinality":"%s","columns":"%s","references":"%s","optional":"%s","kind":"%s","evidence":"%s","tool":"ef-fluent"}\n' \
      "$(json_escape "$from")" "$(json_escape "$to")" "$token" "$(json_escape "$fk")" "$(json_escape "$principal")" "$optional" "$kind" "$(json_escape "$rel")" >>"$EF_RELS"
    printf '{"entity":"%s","name":"%s","type":"declared","nullable":"%s","pk":"no","fk":"yes","evidence":"%s"}\n' \
      "$(json_escape "$from")" "$(json_escape "$fk")" "$optional" "$(json_escape "$rel")" >>"$EF_ATTRS"
  done
  [[ "$ef_bad" -eq 0 ]] || break
done <"$TMP/cs.txt"
set +f

if [[ "$ef_seen" -eq 1 ]]; then
  add_mech ef-fluent orm yes "$ef_evidence"
fi

if [[ -n "$unshipped" ]]; then
  : >"$ENTS"
  : >"$ATTRS"
  : >"$RELS"
  refuse "partial-read"
fi
if [[ -n "$prisma_flag" ]]; then
  : >"$ENTS"
  : >"$ATTRS"
  : >"$RELS"
  add_mech prisma model yes "$first_prisma"
  refuse "$prisma_flag"
fi

# Winner. An unreadable tier refuses the record only when it is the winner. A
# tier that loses and cannot be read is left out of the mismatch comparison and
# reported as not compared.
winner_tool="none"
winner_tier="none"
if [[ -s "$TMP/prisma.txt" ]]; then
  winner_tool="prisma"
  winner_tier="model"
elif [[ "$ef_seen" -eq 1 ]]; then
  winner_tool="ef-fluent"
  winner_tier="orm"
elif [[ -s "$TMP/sql.txt" ]]; then
  winner_tool="sql-migration"
  winner_tier="migration"
else
  refuse "no-declared-schema"
fi

not_compared=0
note_not_compared() {
  printf '{"kind":"not-compared","detail":"%s","evidence":"%s"}\n' \
    "$(json_escape "$1 was not compared with $winner_tool: $2")" "$(json_escape "$3")" >>"$MISMATCHES"
  not_compared=$((not_compared + 1))
}

if [[ "$ef_bad" -eq 1 ]]; then
  ef_why="${ef_why:-a chain outside the readable subset}"
  if [[ "$winner_tool" == "ef-fluent" ]]; then
    printf 'collect-data.sh: ef-fluent unreadable: %s (%s)\n' "$ef_why" "$ef_evidence" >&2
    refuse "ef-fluent-unreadable"
  fi
  note_not_compared ef-fluent "an Entity Framework chain is not in the readable subset: $ef_why" "$ef_evidence"
else
  cat "$EF_ENTS" >>"$ENTS"
  cat "$EF_ATTRS" >>"$ATTRS"
  cat "$EF_RELS" >>"$RELS"
fi
if [[ "$sql_bad" -eq 1 ]]; then
  [[ "$winner_tool" != "sql-migration" ]] || refuse "sql-alter-unreadable"
  note_not_compared sql-migration "an ALTER TABLE form or foreign-key clause is not in the readable subset" "$first_sql"
elif [[ -s "$TMP/sql.txt" ]]; then
  cat "$SQL_ENTS" >>"$ENTS"
  cat "$SQL_ATTRS" >>"$ATTRS"
  cat "$SQL_RELS" >>"$RELS"
fi

# Mark fk flags on attributes whose name is a relationship column. Done in the
# renderer from the relationship list. Attributes stay fk:no unless the EF
# path set them, or a later pass here rewrites prisma/sql rows.
mark_fk() {
  awk '
    FNR == NR && /"from":/ {
      # columns field
      line = $0
      if (match(line, /"from":"[^"]+"/)) {
        from = substr(line, RSTART + 8, RLENGTH - 9)
      }
      if (match(line, /"columns":"[^"]+"/)) {
        cols = substr(line, RSTART + 11, RLENGTH - 12)
        n = split(cols, c, ",")
        for (i = 1; i <= n; i++) fk[from SUBSEP c[i]] = 1
      }
      next
    }
    {
      line = $0
      if (match(line, /"entity":"[^"]+"/)) {
        ent = substr(line, RSTART + 10, RLENGTH - 11)
      } else ent = ""
      if (match(line, /"name":"[^"]+"/)) {
        name = substr(line, RSTART + 8, RLENGTH - 9)
      } else name = ""
      if (ent != "" && name != "" && (ent SUBSEP name) in fk)
        sub(/"fk":"no"/, "\"fk\":\"yes\"")
      print
    }
  ' "$RELS" "$ATTRS" >"$TMP/attrs-marked.json"
  mv "$TMP/attrs-marked.json" "$ATTRS"
}
if [[ -s "$RELS" && -s "$ATTRS" ]]; then
  mark_fk
fi

# Keep only winner entities? No: entities from other shipped tools stay in the
# record so mismatches can name them. The renderer draws the winner tool only.
# Tag is the tool on relationships. Entities do not carry a tool. Mismatch
# comparison uses relationship tool fields.
#
# Drop entities that belong only to a non-winner tool when the winner also
# declared that module, otherwise a SQL-only table in a prisma module shows up
# as a drawn entity. Renderer filters relationships by tool == source_tool and
# entities that are an endpoint of a winner relationship OR have evidence from
# a winner file. Evidence for prisma/sql contains the file path. EF evidence is
# the cs path. Filter here: keep entities whose evidence file extension matches
# the winner, and relationships whose tool matches the winner. Other tools
# relationships are copied aside for mismatch then removed from the drawn set.
# Mismatch rows are computed first.

shipped_tools="$(grep -c '"shipped":"yes"' "$MECH" || true)"
if [[ $((${shipped_tools:-0} - not_compared)) -ge 2 ]]; then
awk -v winner="$winner_tool" -v rels="$RELS" -v mismatches="$MISMATCHES" '
  function field(line, key,    re, s, i) {
    re = "\"" key "\":\""
    i = index(line, re)
    if (i == 0) return ""
    s = substr(line, i + length(re))
    i = index(s, "\"")
    if (i == 0) return ""
    return substr(s, 1, i - 1)
  }
  function jesc(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    return s
  }
  BEGIN { n = 0 }
  {
    n++
    line[n] = $0
    tool[n] = field($0, "tool")
    from[n] = field($0, "from")
    to[n] = field($0, "to")
    cols[n] = field($0, "columns")
    card[n] = field($0, "cardinality")
    opt[n] = field($0, "optional")
    key[n] = from[n] SUBSEP to[n] SUBSEP cols[n]
  }
  END {
    for (i = 1; i <= n; i++) if (tool[i] == winner) win[key[i]] = i
    for (i = 1; i <= n; i++) if (tool[i] != winner) other[key[i]] = i
    for (k in win) {
      if (!(k in other)) {
        i = win[k]
        detail = from[i] "." cols[i] " -> " to[i] " is declared by " winner " and absent from the other shipped tier"
        printf "{\"kind\":\"missing-in-other\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[i], "evidence")) >> mismatches
      } else {
        j = other[k]
        i = win[k]
        if (card[i] != card[j]) {
          detail = from[i] "." cols[i] " cardinality " card[i] " in " winner " and " card[j] " in " tool[j]
          printf "{\"kind\":\"cardinality\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[i], "evidence")) >> mismatches
        }
        if (opt[i] != opt[j]) {
          detail = from[i] "." cols[i] " optionality " opt[i] " in " winner " and " opt[j] " in " tool[j]
          printf "{\"kind\":\"optionality\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[i], "evidence")) >> mismatches
        }
      }
    }
    for (k in other) {
      if (!(k in win)) {
        j = other[k]
        detail = from[j] "." cols[j] " -> " to[j] " is declared by " tool[j] " and absent from " winner
        printf "{\"kind\":\"missing-in-winner\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[j], "evidence")) >> mismatches
      }
    }
  }
' "$RELS"
fi

awk -v winner="$winner_tool" '
  function field(line, key,    re, s, i) {
    re = "\"" key "\":\""
    i = index(line, re)
    if (i == 0) return ""
    s = substr(line, i + length(re))
    i = index(s, "\"")
    if (i == 0) return ""
    return substr(s, 1, i - 1)
  }
  field($0, "tool") == winner { print }
' "$RELS" >"$TMP/rels-win.json"
mv "$TMP/rels-win.json" "$RELS"

if grep -F -q '"cardinality":"unknown"' "$RELS"; then
  : >"$ENTS"
  : >"$ATTRS"
  : >"$RELS"
  : >"$MISMATCHES"
  refuse "unknown-cardinality"
fi

# Entities: keep those whose evidence extension matches the winner tool.
# prisma -> .prisma, sql-migration -> .sql, ef-fluent -> .cs
case "$winner_tool" in
prisma) ext=".prisma" ;;
sql-migration) ext=".sql" ;;
ef-fluent) ext=".cs" ;;
*) ext="" ;;
esac
awk -v ext="$ext" '
  function field(line, key,    re, s, i) {
    re = "\"" key "\":\""
    i = index(line, re)
    if (i == 0) return ""
    s = substr(line, i + length(re))
    i = index(s, "\"")
    if (i == 0) return ""
    return substr(s, 1, i - 1)
  }
  {
    ev = field($0, "evidence")
    if (index(ev, ext) > 0) print
  }
' "$ENTS" >"$TMP/ents-win.json"
mv "$TMP/ents-win.json" "$ENTS"
awk -v ext="$ext" '
  function field(line, key,    re, s, i) {
    re = "\"" key "\":\""
    i = index(line, re)
    if (i == 0) return ""
    s = substr(line, i + length(re))
    i = index(s, "\"")
    if (i == 0) return ""
    return substr(s, 1, i - 1)
  }
  {
    ev = field($0, "evidence")
    if (index(ev, ext) > 0) print
  }
' "$ATTRS" >"$TMP/attrs-win.json"
mv "$TMP/attrs-win.json" "$ATTRS"

# A module is listed only when the winning tier declared an entity in it.
sed -n 's/.*"module":"\([^"]*\)".*/{"id":"\1"}/p' "$ENTS" | sort -u >"$MODS"

# Stable order
sort -o "$MECH" "$MECH"
sort -o "$MODS" "$MODS"
sort -o "$ENTS" "$ENTS"
sort -o "$ATTRS" "$ATTRS"
sort -o "$RELS" "$RELS"
sort -o "$MISMATCHES" "$MISMATCHES"

write_record drawn "" "$winner_tier" "$winner_tool" "$MECH" "$MODS" "$ENTS" "$ATTRS" "$RELS" "$MISMATCHES"
exit 0
