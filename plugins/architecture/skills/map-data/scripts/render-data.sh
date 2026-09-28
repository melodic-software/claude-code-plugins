#!/usr/bin/env bash
# Render data-model.md (and data-model.dbml) from a collect-data.sh record.
#
# Usage:
#   render-data.sh --record <data-model.json> --out <dir>
#       [--dialect mermaid|dbml] [--scope module|all|<module>] [--include-columns]
#   render-data.sh --help
#
# The record is schema_version 1, one object per line. Any other layout exits 1
# and writes nothing.
#
# --scope module (the default) draws the only module. Several modules write a
# refusal that names them and exit 3. No diagram is drawn until the scope is
# one module or all.
#
# Exit: 0 = artifact written (a collected refusal is still exit 0); 1 = the
# record is unreadable; 2 = usage; 3 = scope unresolved, refusal written.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-data.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
out=""
dialect="mermaid"
scope="module"
columns=0

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
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    out="$2"
    shift 2
    ;;
  --dialect)
    [[ $# -ge 2 ]] || die "--dialect needs a value" 2
    dialect="$2"
    shift 2
    ;;
  --scope)
    [[ $# -ge 2 ]] || die "--scope needs a value" 2
    scope="$2"
    shift 2
    ;;
  --include-columns)
    columns=1
    shift
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

[[ -n "$record" && -n "$out" ]] || die "--record and --out are required" 2
[[ -f "$record" ]] || die "record is not a file: $record" 1
[[ "$dialect" == "mermaid" || "$dialect" == "dbml" ]] || die "dialect must be mermaid or dbml" 2

mkdir -p "$out"
md="$out/data-model.md"
dbml="$out/data-model.dbml"

set +e
summary="$(
  awk -v dialect="$dialect" -v scope_arg="$scope" -v columns="$columns" -v md="$md" -v dbml="$dbml" '
    function die(msg) { printf "render-data.sh: %s\n", msg > "/dev/stderr"; exit 1 }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function field(line, key,    re, rest, i) {
      re = "\"" key "\":"
      i = index(line, re)
      if (i == 0) return ""
      rest = substr(line, i + length(re))
      sub(/^[[:space:]]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") return ""
      rest = substr(rest, 2)
      i = index(rest, "\"")
      if (i == 0) return ""
      return substr(rest, 1, i - 1)
    }
    function unesc(s) {
      gsub(/\\"/, "\"", s)
      gsub(/\\\\/, "\\", s)
      return s
    }
    function jget(line, key) { return unesc(field(line, key)) }
    function safe(s) {
      gsub(/"/, "'\''", s)
      gsub(/\|/, "/", s)
      return s
    }
    function mtype(t,    x) {
      x = tolower(t)
      if (x ~ /^(int|integer|bigint|smallint|serial)$/) return "int"
      if (x ~ /^(string|text|varchar|char|nvarchar|citext)$/) return "string"
      if (x ~ /^(bool|boolean)$/) return "boolean"
      if (x ~ /^(datetime|timestamp|date|time)$/) return "datetime"
      if (x ~ /^(float|double|decimal|numeric|real)$/) return "float"
      if (x ~ /^[a-z][a-z0-9_]*$/) return x
      return "string"
    }
    function take_array(first, key, prefix,    line, item) {
      line = trim(first)
      if (line == "\"" key "\": []" || line == "\"" key "\": [],") return
      if (line != "\"" key "\": [") die(key " is not one object per line or []")
      while ((getline line) > 0) {
        item = trim(line)
        if (item == "]" || item == "],") return
        sub(/,$/, "", item)
        if (index(item, prefix) != 1) die(key " line is not one " prefix " object")
        nkey++
        held[key, nkey] = item
        count[key]++
        idx[key, count[key]] = nkey
      }
      die(key " array was not closed")
    }
    function reason_prose(r) {
      if (r == "live-connection-requested")
        return "A live connection was requested. No live adapter is shipped, and offline declarations were not read. No diagram was drawn."
      if (r == "partial-read")
        return "More than one schema mechanism is declared, and at least one has no shipped adapter. Drawing the shipped subset would be a partial read. No diagram was drawn."
      if (r == "no-declared-schema")
        return "No shipped schema declaration was found in tracked files. No diagram was drawn."
      if (r == "not-a-git-repository")
        return "The subject is not a git repository, so tracked declarations cannot be separated from untracked files. No diagram was drawn."
      if (r == "implicit-many-to-many")
        return "A Prisma schema declares a many-to-many with no foreign-key fields. Cardinality was not guessed. No diagram was drawn."
      if (r == "ef-fluent-unreadable")
        return "An Entity Framework fluent chain is present but not in the shipped shape (Entity<T>, HasOne<T> or HasMany<T>, HasForeignKey(\"Column\"), IsRequired or IsRequired(false)). No diagram was drawn."
      if (r == "unsupported")
        return "A Prisma schema contains a block comment or another construct this adapter does not read. No diagram was drawn."
      if (r == "unresolved-target" || r == "unreadable-relation")
        return "A Prisma relation does not name a model and foreign-key fields in the same schema file. No diagram was drawn."
      if (r == "optionality-disagrees")
        return "A Prisma relation field and its scalar foreign key disagree on optionality. The conflict was not resolved. No diagram was drawn."
      if (r == "scope-unresolved")
        return "More than one module declares a schema. Pass --scope <module> or --scope all. No diagram was drawn."
      if (r == "unknown-module")
        return "The requested module is not in the record. No diagram was drawn."
      return "The record refused to draw a diagram."
    }
    BEGIN {
      if ((getline line) <= 0) die("empty record")
      if (trim(line) != "{") die("record does not start with an object")
      if ((getline line) <= 0) die("missing schema_version")
      if (trim(line) != "\"schema_version\": 1,") die("not schema_version 1")
      while ((getline line) > 0) {
        t = trim(line)
        if (t == "}") break
        if (t ~ /^"generated_on":/) generated = jget(t, "generated_on")
        else if (t ~ /^"subject":/) subject = jget(t, "subject")
        else if (t ~ /^"status":/) status = jget(t, "status")
        else if (t ~ /^"reason":/) reason = jget(t, "reason")
        else if (t ~ /^"source_tier":/) tier = jget(t, "source_tier")
        else if (t ~ /^"source_tool":/) tool = jget(t, "source_tool")
        else if (t ~ /^"mechanisms":/) { nkey = 0; take_array(t, "mechanisms", "{\"name\":") }
        else if (t ~ /^"modules":/) { nkey = 0; take_array(t, "modules", "{\"id\":") }
        else if (t ~ /^"entities":/) { nkey = 0; take_array(t, "entities", "{\"id\":") }
        else if (t ~ /^"attributes":/) { nkey = 0; take_array(t, "attributes", "{\"entity\":") }
        else if (t ~ /^"relationships":/) { nkey = 0; take_array(t, "relationships", "{\"from\":") }
        else if (t ~ /^"mismatches":/) { nkey = 0; take_array(t, "mismatches", "{\"kind\":") }
        else if (t ~ /^"[a-z_]+": \[$/) die("unknown array " t)
      }
      if (status != "drawn" && status != "refused") die("status is missing")
      nm = count["modules"] + 0
      for (i = 1; i <= nm; i++) {
        item = held["modules", idx["modules", i]]
        mid[i] = jget(item, "id")
      }
      # sort module ids
      for (i = 1; i <= nm; i++) for (j = i + 1; j <= nm; j++) if (mid[j] < mid[i]) { tmp = mid[i]; mid[i] = mid[j]; mid[j] = tmp }
      ne = count["entities"] + 0
      for (i = 1; i <= ne; i++) {
        item = held["entities", idx["entities", i]]
        eid[i] = jget(item, "id")
        ename[i] = jget(item, "name")
        emod[i] = jget(item, "module")
        eev[i] = jget(item, "evidence")
        name_of[eid[i]] = ename[i]
      }
      na = count["attributes"] + 0
      for (i = 1; i <= na; i++) {
        item = held["attributes", idx["attributes", i]]
        aent[i] = jget(item, "entity")
        aname[i] = jget(item, "name")
        atype[i] = jget(item, "type")
        anull[i] = jget(item, "nullable")
        apk[i] = jget(item, "pk")
        afk[i] = jget(item, "fk")
        aev[i] = jget(item, "evidence")
      }
      nr = count["relationships"] + 0
      for (i = 1; i <= nr; i++) {
        item = held["relationships", idx["relationships", i]]
        rfrom[i] = jget(item, "from")
        rto[i] = jget(item, "to")
        rcard[i] = jget(item, "cardinality")
        rcols[i] = jget(item, "columns")
        ropt[i] = jget(item, "optional")
        rev[i] = jget(item, "evidence")
      }
      nmis = count["mismatches"] + 0
      nmech = count["mechanisms"] + 0
      exit_code = 0
      selected = ""
      if (status == "refused") {
        draw = 0
        scope_out = "none"
      } else if (scope_arg == "all") {
        draw = 1
        scope_out = "all"
        for (i = 1; i <= nm; i++) in_scope[mid[i]] = 1
      } else if (scope_arg == "module" || scope_arg == "") {
        if (nm == 1) {
          draw = 1
          scope_out = mid[1]
          in_scope[mid[1]] = 1
        } else if (nm == 0) {
          draw = 1
          scope_out = "none"
        } else {
          draw = 0
          status = "refused"
          reason = "scope-unresolved"
          scope_out = "unresolved"
          exit_code = 3
        }
      } else {
        found = 0
        for (i = 1; i <= nm; i++) if (mid[i] == scope_arg) found = 1
        if (!found) {
          draw = 0
          status = "refused"
          reason = "unknown-module"
          scope_out = scope_arg
          exit_code = 3
        } else {
          draw = 1
          scope_out = scope_arg
          in_scope[scope_arg] = 1
        }
      }
      print "# Data model" > md
      print "" > md
      print "Generated on " generated "." > md
      print "" > md
      print "Subject: " safe(subject) "." > md
      print "" > md
      print "Status: " status "." > md
      print "" > md
      if (status == "refused") {
        print "Reason: " reason "." > md
        print "" > md
        print reason_prose(reason) > md
        print "" > md
      } else {
        print "Source tier: " tier " (" tool ")." > md
        print "" > md
        print "Dialect: " dialect ". The key is diagram_dialect.data (mermaid or dbml, default mermaid)." > md
        print "" > md
        print "Scope: " scope_out "." > md
        print "" > md
        if (columns) print "Columns: included." > md
        else print "Columns: omitted. Pass --include-columns to show them." > md
        print "" > md
      }
      print "## Mechanisms" > md
      print "" > md
      if (nmech == 0) {
        print "No schema mechanism was recognized." > md
        print "" > md
      } else {
        print "| Name | Tier | Shipped | Evidence |" > md
        print "|---|---|---|---|" > md
        for (i = 1; i <= nmech; i++) {
          item = held["mechanisms", idx["mechanisms", i]]
          print "| " safe(jget(item, "name")) " | " safe(jget(item, "tier")) " | " safe(jget(item, "shipped")) " | " safe(jget(item, "evidence")) " |" > md
        }
        print "" > md
      }
      if (reason == "scope-unresolved" || reason == "unknown-module") {
        print "## Modules" > md
        print "" > md
        if (nm == 0) print "None." > md
        for (i = 1; i <= nm; i++) print "- " safe(mid[i]) > md
        print "" > md
      }
      print "## Mismatches" > md
      print "" > md
      if (nmis == 0) {
        print "None." > md
        print "" > md
      } else {
        print "| Kind | Detail | Evidence |" > md
        print "|---|---|---|" > md
        for (i = 1; i <= nmis; i++) {
          item = held["mismatches", idx["mismatches", i]]
          print "| " safe(jget(item, "kind")) " | " safe(jget(item, "detail")) " | " safe(jget(item, "evidence")) " |" > md
        }
        print "" > md
      }
      drawn_e = 0
      drawn_r = 0
      if (draw) {
        print "## Diagram" > md
        print "" > md
        # select entities
        for (i = 1; i <= ne; i++) if (nm == 0 || (emod[i] in in_scope) || scope_out == "all") {
          if (scope_out == "all" || nm == 0 || (emod[i] in in_scope)) {
            drawn_e++
            keep_e[eid[i]] = 1
            show_e[drawn_e] = i
          }
        }
        next_r = 0
        for (i = 1; i <= nr; i++) {
          fin = (rfrom[i] in keep_e)
          tin = (rto[i] in keep_e)
          if (fin && tin) {
            drawn_r++
            show_r[drawn_r] = i
          } else if (fin || tin) {
            next_r++
            outside[next_r] = i
          }
        }
        if (drawn_e == 0) {
          print "No entities were declared in the selected scope. No diagram was drawn." > md
          print "" > md
        } else if (dialect == "mermaid") {
          print "```mermaid" > md
          print "erDiagram" > md
          for (i = 1; i <= drawn_e; i++) {
            ei = show_e[i]
            id = eid[ei]
            if (columns) {
              any = 0
              for (a = 1; a <= na; a++) if (aent[a] == id) any = 1
              if (!any) print "  " safe(ename[ei]) > md
              else {
                print "  " safe(ename[ei]) " {" > md
                for (a = 1; a <= na; a++) if (aent[a] == id) {
                  mark = ""
                  if (apk[a] == "yes" && afk[a] == "yes") mark = " PK, FK"
                  else if (apk[a] == "yes") mark = " PK"
                  else if (afk[a] == "yes") mark = " FK"
                  print "    " mtype(atype[a]) " " safe(aname[a]) mark > md
                }
                print "  }" > md
              }
            } else {
              print "  " safe(ename[ei]) > md
            }
          }
          for (i = 1; i <= drawn_r; i++) {
            ri = show_r[i]
            print "  " safe(name_of[rto[ri]]) " " rcard[ri] " " safe(name_of[rfrom[ri]]) " : \"" safe(rcols[ri]) "\"" > md
          }
          print "```" > md
          print "" > md
        } else {
          print "The diagram is data-model.dbml." > md
          print "" > md
          print "// Generated on " safe(generated) "." > dbml
          print "// Source tier: " safe(tier) " (" safe(tool) ")." > dbml
          print "// Columns: " (columns ? "included" : "omitted") "." > dbml
          for (i = 1; i <= drawn_e; i++) {
            ei = show_e[i]
            id = eid[ei]
            print "Table \"" safe(ename[ei]) "\" {" > dbml
            if (columns) {
              for (a = 1; a <= na; a++) if (aent[a] == id) {
                flags = ""
                if (apk[a] == "yes") flags = flags "pk"
                if (anull[a] == "yes") flags = (flags == "" ? "null" : flags ", null")
                if (flags == "") print "  " safe(aname[a]) " " mtype(atype[a]) > dbml
                else print "  " safe(aname[a]) " " mtype(atype[a]) " [" flags "]" > dbml
              }
            }
            print "}" > dbml
          }
          for (i = 1; i <= drawn_r; i++) {
            ri = show_r[i]
            op = (ropt[ri] == "yes" ? "one-to-one" : "")
            # kind is recovered from the token
            if (rcard[ri] == "||--||" || rcard[ri] == "||--o|") op = "-"
            else op = ">"
            print "Ref: \"" safe(name_of[rfrom[ri]]) "\".\"" safe(rcols[ri]) "\" " op " \"" safe(name_of[rto[ri]]) "\".\"id\"" > dbml
          }
        }
        if (next_r > 0) {
          print "## Outside the scope" > md
          print "" > md
          print "These relationships name an entity outside the selected module and were not drawn." > md
          print "" > md
          for (i = 1; i <= next_r; i++) {
            ri = outside[i]
            print "- " safe(rfrom[ri]) " -> " safe(rto[ri]) " (" safe(rcols[ri]) ")" > md
          }
          print "" > md
        }
        print "## Relationships" > md
        print "" > md
        if (drawn_r == 0) {
          print "None in scope." > md
          print "" > md
        } else {
          print "| From | To | Cardinality | Columns | Optional | Evidence |" > md
          print "|---|---|---|---|---|---|" > md
          for (i = 1; i <= drawn_r; i++) {
            ri = show_r[i]
            print "| " safe(name_of[rfrom[ri]]) " | " safe(name_of[rto[ri]]) " | " rcard[ri] " | " safe(rcols[ri]) " | " ropt[ri] " | " safe(rev[ri]) " |" > md
          }
          print "" > md
        }
        if (columns) {
          print "## Columns" > md
          print "" > md
          print "| Entity | Column | Type | Nullable | PK | FK | Evidence |" > md
          print "|---|---|---|---|---|---|---|" > md
          for (a = 1; a <= na; a++) if (aent[a] in keep_e) {
            print "| " safe(name_of[aent[a]]) " | " safe(aname[a]) " | " safe(atype[a]) " | " anull[a] " | " apk[a] " | " afk[a] " | " safe(aev[a]) " |" > md
          }
          print "" > md
        }
      }
      colflag = (columns ? "yes" : "no")
      printf "data: status=%s reason=%s tier=%s tool=%s modules=%d entities=%d relationships=%d mismatches=%d columns=%s dialect=%s scope=%s\n", \
        status, (reason == "" ? "none" : reason), (tier == "" ? "none" : tier), (tool == "" ? "none" : tool), nm, drawn_e + 0, drawn_r + 0, nmis, colflag, dialect, scope_out
      exit exit_code
    }
  ' "$record"
)"
rc=$?
set -e
if [[ $rc -ne 0 && $rc -ne 3 ]]; then
  rm -f "$md" "$dbml"
  exit "$rc"
fi
printf '%s\n' "$summary"
exit "$rc"
