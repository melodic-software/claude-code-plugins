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
#   2. orm        Entity Framework fluent chains with an IsRequired declaration
#   3. migration  SQL under a migrations directory
#
# A recognized mechanism this script does not extract (Django models, SQLAlchemy
# columns, EF [ForeignKey] annotations, an EF chain it cannot read, implicit
# Prisma many-to-many) refuses the record. A shipped diagram plus an unread
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
# (||--o{ is one referenced row to zero-or-more foreign-key rows).
#
# Portability: bash plus POSIX awk. No jq, no python, no database client.
#
# Exit: 0 = a record was written (including a refusal); 1 = the path is not a
# readable directory; 2 = usage.
set -uo pipefail

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

github_repo_name() {
  local url="$1" scheme=0 host rest host_l repo
  [[ -n "$url" && "$url" != "unknown" ]] || return 1
  url="${url%/}"
  url="${url%.git}"
  [[ "$url" == *://* ]] && scheme=1 && url="${url#*://}"
  [[ "${url%%/*}" == *@* ]] && url="${url#*@}"
  host="${url%%[:/]*}"
  rest="${url#"$host"}"
  if [[ $scheme -eq 1 ]]; then
    [[ "$rest" =~ ^:[0-9]*/ ]] && rest="${rest#:*/}"
    if [[ "$rest" == :* ]]; then
      return 1
    fi
    rest="${rest#/}"
  else
    [[ "$rest" == :* ]] || return 1
    rest="${rest#:}"
    rest="${rest#/}"
  fi
  [[ -n "$rest" ]] || return 1
  host_l="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [[ "$host_l" == "github.com" || "$host_l" == "www.github.com" ]] || return 1
  repo="${rest#*/}"
  repo="${repo%%/*}"
  [[ -n "$repo" && "$repo" != "$rest" ]] || return 1
  printf '%s' "$repo"
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
MIS="$TMP/mismatches.tsv"
empty_tsvs "$MECH" "$MODS" "$ENTS" "$ATTRS" "$RELS" "$MIS"

refuse() {
  local reason="$1"
  write_record refused "$reason" none none "$MECH" "$MODS" "$ENTS" "$ATTRS" "$RELS" "$MIS"
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

add_module() {
  local id="$1"
  local esc
  esc="$(json_escape "$id")"
  if ! grep -F -q "\"id\":\"$esc\"" "$MODS" 2>/dev/null; then
    printf '{"id":"%s"}\n' "$esc" >>"$MODS"
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
  [[ -f "$repo/$rel" ]] || continue
  case "$rel" in
  *.prisma)
    printf '%s\n' "$rel" >>"$TMP/prisma.txt"
    add_module "$(module_of "$rel")"
    ;;
  *.sql)
    case "$rel" in
    */migrations/* | */Migrations/*)
      printf '%s\n' "$rel" >>"$TMP/sql.txt"
      add_module "$(module_of "$rel")"
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
    [[ -f "$repo/$rel" ]] || continue
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
    [[ -f "$repo/$rel" ]] || continue
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
        nsplit = split(cols, col, ",")
        all_unique = 1
        any_opt = field_opt[i]
        disagree = 0
        for (c = 1; c <= nsplit; c++) {
          key = field_model[i] SUBSEP col[c]
          if (!(key in scalar_unique) || scalar_unique[key] != 1) all_unique = 0
          if (key in scalar_opt) {
            if (scalar_opt[key] != field_opt[i]) disagree = 1
            if (scalar_opt[key]) any_opt = 1
          }
        }
        if (disagree) {
          printf "optionality-disagrees\n" > out_flag
          exit 0
        }
        kind = (all_unique ? "one-to-one" : "one-to-many")
        if (kind == "one-to-one") {
          token = (any_opt ? "||--o|" : "||--||")
        } else {
          token = (any_opt ? "|o--o{" : "||--o{")
        }
        opt = (any_opt ? "yes" : "no")
        from = entity_id(module, field_model[i])
        to = entity_id(module, field_base[i])
        printf "{\"from\":\"%s\",\"to\":\"%s\",\"cardinality\":\"%s\",\"columns\":\"%s\",\"optional\":\"%s\",\"kind\":\"%s\",\"evidence\":\"%s\",\"tool\":\"prisma\"}\n", \
          jesc(from), jesc(to), token, jesc(cols), opt, kind, jesc(path ":" field_line[i]) >> out_rels
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


if [[ -s "$TMP/sql.txt" ]]; then
  : >"$TMP/sql-replay.sql"
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    {
      printf '%s\n' "-- MAPDATA FILE $rel"
      cat "$repo/$rel"
      printf '\n'
    } >>"$TMP/sql-replay.sql"
  done < <(sort "$TMP/sql.txt")
  # One replay across every migration file. The sentinel carries the path so
  # evidence and module follow the file that declared the row. A later
  # DROP TABLE removes the entity from the final shape.
  awk -v ents="$ENTS" -v attrs="$ATTRS" -v rels="$RELS" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function stripq(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (substr(s, 1, 1) == "\"") { sub(/^"/, "", s); sub(/"$/, "", s) }
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
    function forget(name,    eid, i) {
      eid = entity_id(module, name)
      for (i = 1; i <= nent; i++) if (ent_id[i] == eid) ent_dead[i] = 1
      for (i = 1; i <= nattr; i++) if (attr_entity[i] == eid) attr_dead[i] = 1
      for (i = 1; i <= nrel; i++) if (rel_from[i] == eid || rel_to[i] == eid) rel_dead[i] = 1
    }
    BEGIN { path = ""; module = "."; inn = 0; fline = 0 }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw ~ /^-- MAPDATA FILE /) {
        path = substr(raw, 17)
        module = module_of(path)
        inn = 0
        fline = 0
        next
      }
      fline++
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
        inn = 1
        cur = tname
        eid = entity_id(module, cur)
        nent++
        ent_id[nent] = eid
        ent_dead[nent] = 0
        ent_line[nent] = sprintf("{\"id\":\"%s\",\"name\":\"%s\",\"module\":\"%s\",\"evidence\":\"%s\"}", jesc(eid), jesc(cur), jesc(module), jesc(path ":" fline))
        next
      }
      if (inn && up ~ /^[ \t]*\)[ \t]*;/) { inn = 0; cur = ""; next }
      if (!inn) next
      if (up ~ /FOREIGN[ \t]+KEY/) {
        tmp = line
        sub(/.*[Ff][Oo][Rr][Ee][Ii][Gg][Nn][ \t]+[Kk][Ee][Yy][ \t]*/, "", tmp)
        sub(/^[ \t]*\(/, "", tmp)
        cols = tmp
        sub(/\).*/, "", cols)
        gsub(/[[:space:]]/, "", cols)
        nsplit = split(cols, col, ",")
        cjoined = ""
        for (c = 1; c <= nsplit; c++) {
          col[c] = stripq(col[c])
          if (c > 1) cjoined = cjoined ","
          cjoined = cjoined col[c]
        }
        rest = line
        sub(/.*[Rr][Ee][Ff][Ee][Rr][Ee][Nn][Cc][Ee][Ss][ \t]*/, "", rest)
        refname = rest
        sub(/[ \t]*\(.*/, "", refname)
        refname = stripq(trim(refname))
        all_unique = 1
        any_opt = 0
        for (c = 1; c <= nsplit; c++) {
          ukey = cur SUBSEP col[c]
          if (!(ukey in uniq) || uniq[ukey] != 1) all_unique = 0
          if (ukey in nulls && nulls[ukey] == 1) any_opt = 1
        }
        kind = (all_unique ? "one-to-one" : "one-to-many")
        if (kind == "one-to-one") token = (any_opt ? "||--o|" : "||--||")
        else token = (any_opt ? "|o--o{" : "||--o{")
        opt = (any_opt ? "yes" : "no")
        from = entity_id(module, cur)
        to = entity_id(module, refname)
        nrel++
        rel_from[nrel] = from
        rel_to[nrel] = to
        rel_dead[nrel] = 0
        rel_line[nrel] = sprintf("{\"from\":\"%s\",\"to\":\"%s\",\"cardinality\":\"%s\",\"columns\":\"%s\",\"optional\":\"%s\",\"kind\":\"%s\",\"evidence\":\"%s\",\"tool\":\"sql-migration\"}", jesc(from), jesc(to), token, jesc(cjoined), opt, kind, jesc(path ":" fline))
        next
      }
      if (up ~ /UNIQUE/ && up ~ /\(/) {
        tmp = line
        sub(/.*\(/, "", tmp)
        sub(/\).*/, "", tmp)
        gsub(/[[:space:]]/, "", tmp)
        nsplit = split(tmp, col, ",")
        for (c = 1; c <= nsplit; c++) uniq[cur SUBSEP stripq(col[c])] = 1
        next
      }
      if (up ~ /^[ \t]*(CONSTRAINT|PRIMARY|CHECK|INDEX)[ \t]/) next
      stripped = trim(line)
      sub(/,$/, "", stripped)
      if (stripped == "" || stripped ~ /^\(/) next
      ntok = split(stripped, tok, /[ \t]+/)
      if (ntok < 2) next
      cname = stripq(tok[1])
      if (toupper(cname) == "CONSTRAINT") next
      ctype = tok[2]
      sub(/,$/, "", ctype)
      nullable = "yes"
      if (up ~ /NOT[ \t]+NULL/) nullable = "no"
      pk = "no"
      if (up ~ /PRIMARY[ \t]+KEY/) { pk = "yes"; uniq[cur SUBSEP cname] = 1 }
      if (up ~ /UNIQUE/ && up !~ /UNIQUE[ \t]*\(/) uniq[cur SUBSEP cname] = 1
      nulls[cur SUBSEP cname] = (nullable == "yes" ? 1 : 0)
      nattr++
      attr_entity[nattr] = entity_id(module, cur)
      attr_dead[nattr] = 0
      attr_line[nattr] = sprintf("{\"entity\":\"%s\",\"name\":\"%s\",\"type\":\"%s\",\"nullable\":\"%s\",\"pk\":\"%s\",\"fk\":\"no\",\"evidence\":\"%s\"}", jesc(entity_id(module, cur)), jesc(cname), jesc(ctype), nullable, pk, jesc(path ":" fline))
    }
    END {
      for (i = 1; i <= nent; i++) if (!ent_dead[i]) print ent_line[i] >> ents
      for (i = 1; i <= nattr; i++) if (!attr_dead[i]) print attr_line[i] >> attrs
      for (i = 1; i <= nrel; i++) if (!rel_dead[i]) print rel_line[i] >> rels
    }
  ' "$TMP/sql-replay.sql"
fi

# --- EF fluent --------------------------------------------------------------
ef_seen=0
ef_bad=0
ef_evidence=""
set -f
while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  [[ -f "$repo/$rel" ]] || continue
  if ! grep -E -q 'Has(One|Many|ForeignKey)' "$repo/$rel"; then
    continue
  fi
  ef_seen=1
  ef_evidence="$rel"
  module="$(module_of "$rel")"
  add_module "$module"
  flattened="$(sed -E 's://.*$::' "$repo/$rel" | tr '\n' ' ')"
  IFS=';' read -r -a statements <<<"$flattened"
  for part in "${statements[@]}"; do
    [[ "$part" == *HasOne* || "$part" == *HasMany* || "$part" == *HasForeignKey* ]] || continue
    configured="" one="" many="" fk=""
    [[ "$part" =~ Entity\<([A-Za-z_][A-Za-z0-9_]*)\> ]] && configured="${BASH_REMATCH[1]}"
    [[ "$part" =~ HasOne\<([A-Za-z_][A-Za-z0-9_]*)\> ]] && one="${BASH_REMATCH[1]}"
    [[ "$part" =~ HasMany\<([A-Za-z_][A-Za-z0-9_]*)\> ]] && many="${BASH_REMATCH[1]}"
    [[ "$part" =~ HasForeignKey\(\"([A-Za-z_][A-Za-z0-9_]*)\"\) ]] && fk="${BASH_REMATCH[1]}"
    if [[ -z "$configured" || -z "$fk" ]]; then
      ef_bad=1
      break
    fi
    if [[ -n "$one" && -n "$many" ]]; then
      ef_bad=1
      break
    fi
    optional=""
    if [[ "$part" =~ IsRequired\(false\) ]]; then
      optional="yes"
    elif [[ "$part" =~ IsRequired\(\) ]]; then
      optional="no"
    else
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
    elif [[ -n "$one" && "$part" == *WithOne* ]]; then
      fk_entity="$configured"
      pk_entity="$one"
      kind="one-to-one"
    else
      ef_bad=1
      break
    fi
    if [[ "$kind" == "one-to-one" ]]; then
      token="$([[ "$optional" == "yes" ]] && printf '||--o|' || printf '||--||')"
    else
      token="$([[ "$optional" == "yes" ]] && printf '|o--o{' || printf '||--o{')"
    fi
    from="$(entity_id "$module" "$fk_entity")"
    to="$(entity_id "$module" "$pk_entity")"
    # entities (once)
    for pair in "$fk_entity" "$pk_entity"; do
      eid="$(entity_id "$module" "$pair")"
      esc_id="$(json_escape "$eid")"
      if ! grep -F -q "\"id\":\"$esc_id\"" "$ENTS"; then
        printf '{"id":"%s","name":"%s","module":"%s","evidence":"%s"}\n' \
          "$esc_id" "$(json_escape "$pair")" "$(json_escape "$module")" "$(json_escape "$rel")" >>"$ENTS"
      fi
    done
    printf '{"from":"%s","to":"%s","cardinality":"%s","columns":"%s","optional":"%s","kind":"%s","evidence":"%s","tool":"ef-fluent"}\n' \
      "$(json_escape "$from")" "$(json_escape "$to")" "$token" "$(json_escape "$fk")" "$optional" "$kind" "$(json_escape "$rel")" >>"$RELS"
    printf '{"entity":"%s","name":"%s","type":"declared","nullable":"%s","pk":"no","fk":"yes","evidence":"%s"}\n' \
      "$(json_escape "$from")" "$(json_escape "$fk")" "$optional" "$(json_escape "$rel")" >>"$ATTRS"
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
if [[ "$ef_bad" -eq 1 ]]; then
  : >"$ENTS"
  : >"$ATTRS"
  : >"$RELS"
  refuse "ef-fluent-unreadable"
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

# Winner
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
if [[ "${shipped_tools:-0}" -ge 2 ]]; then
awk -v winner="$winner_tool" -v rels="$RELS" -v mis="$MIS" '
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
        printf "{\"kind\":\"missing-in-other\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[i], "evidence")) >> mis
      } else {
        j = other[k]
        i = win[k]
        if (card[i] != card[j]) {
          detail = from[i] "." cols[i] " cardinality " card[i] " in " winner " and " card[j] " in " tool[j]
          printf "{\"kind\":\"cardinality\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[i], "evidence")) >> mis
        }
        if (opt[i] != opt[j]) {
          detail = from[i] "." cols[i] " optionality " opt[i] " in " winner " and " opt[j] " in " tool[j]
          printf "{\"kind\":\"optionality\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[i], "evidence")) >> mis
        }
      }
    }
    for (k in other) {
      if (!(k in win)) {
        j = other[k]
        detail = from[j] "." cols[j] " -> " to[j] " is declared by " tool[j] " and absent from " winner
        printf "{\"kind\":\"missing-in-winner\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", jesc(detail), jesc(field(line[j], "evidence")) >> mis
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

# Stable order
sort -o "$MECH" "$MECH"
sort -o "$MODS" "$MODS"
sort -o "$ENTS" "$ENTS"
sort -o "$ATTRS" "$ATTRS"
sort -o "$RELS" "$RELS"
sort -o "$MIS" "$MIS"

write_record drawn "" "$winner_tier" "$winner_tool" "$MECH" "$MODS" "$ENTS" "$ATTRS" "$RELS" "$MIS"
exit 0
