#!/usr/bin/env bash
# Inventory the provenance signals already present in markdown: URLs, HTML
# comment fences, stamp lines, and blockquote lines.
#
#   extract-breadcrumbs.sh --dir D | --files F...
#
# Reasoning-free (Brief constraint C1): this script EXTRACTS breadcrumbs and
# makes no judgment about which breadcrumb explains which passage, or whether a
# passage is a copy at all. Both of those are model work downstream.
#
# Output is grouped PER DIRECTORY, not per file, because spike S1 resolved a
# real cross-file breadcrumb: a neighbor's citation named the source of an
# unfenced copy. Handing the resolving step one file's breadcrumbs would have
# lost that. `--dir` is deliberately non-recursive — the group is the sibling
# set, and a subtree's files are their own siblings.
#
# Two shapes the design docs describe in prose and this script settles:
#
#   1. A fence is an HTML comment carrying a URL. `start_line`/`end_line` is the
#      comment's own extent, unless a later comment whose body begins with `/`
#      closes it (the `<!-- /provenance -->` idiom), in which case the span runs
#      to the closer. No marker vocabulary is invented or required: a repo that
#      has no fence convention still gets its URL-carrying comments inventoried.
#   2. A stamp line is a stamp keyword followed, within a short window, by
#      something date-shaped. A date with no keyword is not a stamp (a changelog
#      entry is not a verification record), and a keyword with no date is not
#      one either ("confirmed from a primary" is prose). This script only
#      inventories them; check-stamps.sh decides what parses and what expires.
#
# A URL inside an HTML comment is reported as that fence's source_url and not
# again under `urls`, so one breadcrumb is counted once.
#
# Contract: docs/topics/copied-external-content/design/type-inventory.md.
# Exit: 0 on a clean run, 2 on usage error or an unreadable input path.
set -uo pipefail

MODE=""
DIR=""
FILES=()

usage() {
  cat <<'EOF'
extract-breadcrumbs.sh — inventory provenance signals in markdown.

Usage:
  extract-breadcrumbs.sh --dir D
  extract-breadcrumbs.sh --files F [F...]

  --dir D     the markdown files directly in D (non-recursive: the sibling set)
  --files F   explicit files, grouped by their directories

Output: JSON on stdout — {directories: [{dir, files: [{file, urls, fences,
stamp_lines, quote_lines}]}], counts}. Diagnostics go to stderr.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dir)
    if [[ -n "$MODE" ]]; then
      echo "extract-breadcrumbs.sh: --dir and --files are exclusive" >&2
      exit 2
    fi
    if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
      echo "extract-breadcrumbs.sh: --dir requires a value" >&2
      exit 2
    fi
    MODE="dir"
    DIR="$2"
    shift 2
    ;;
  --files)
    if [[ -n "$MODE" ]]; then
      echo "extract-breadcrumbs.sh: --dir and --files are exclusive" >&2
      exit 2
    fi
    MODE="files"
    shift
    while [[ $# -gt 0 && "$1" != -* ]]; do
      FILES+=("$1")
      shift
    done
    if [[ "${#FILES[@]}" -eq 0 ]]; then
      echo "extract-breadcrumbs.sh: --files requires at least one path" >&2
      exit 2
    fi
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "extract-breadcrumbs.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "extract-breadcrumbs.sh: one of --dir or --files is required" >&2
  usage >&2
  exit 2
fi

if [[ "$MODE" == "dir" ]]; then
  if [[ ! -d "$DIR" ]]; then
    echo "extract-breadcrumbs.sh: not a directory: $DIR" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && FILES+=("$line")
  done < <(find "$DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)
else
  for f in "${FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "extract-breadcrumbs.sh: not a readable file: $f" >&2
      exit 2
    fi
  done
fi

# --- Grouping --------------------------------------------------------------------

GROUP_DIRS=()
declare -A GROUP_MEMBERS=()

for f in ${FILES[@]+"${FILES[@]}"}; do
  d="$(dirname "$f")"
  if [[ -z "${GROUP_MEMBERS[$d]:-}" ]]; then
    GROUP_DIRS+=("$d")
    GROUP_MEMBERS["$d"]=""
  fi
  GROUP_MEMBERS["$d"]="${GROUP_MEMBERS[$d]}${f}"$'\n'
done

if [[ "${#GROUP_DIRS[@]}" -gt 1 ]]; then
  mapfile -t GROUP_DIRS < <(printf '%s\n' "${GROUP_DIRS[@]}" | LC_ALL=C sort)
fi

# --- Per-file extraction ---------------------------------------------------------

# One awk pass per directory group. LC_ALL=C makes substr/length byte-wise,
# which keeps multibyte text passing through unchanged while making the
# control-character guard in jesc() well-defined.
extract_group() {
  LC_ALL=C awk '
function jesc(s,   out, i, c) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\") out = out "\\\\"
    else if (c == "\"") out = out "\\\""
    else if (c == "\t") out = out "\\t"
    else if (c == "\r") out = out "\\r"
    else if (c < " ") out = out " "
    else out = out c
  }
  return out
}

function trim(s) {
  sub(/^[ \t\r]+/, "", s)
  sub(/[ \t\r]+$/, "", s)
  return s
}

function first_url(s,   m) {
  if (match(s, /https?:\/\/[^][ \t()<>"`{}]+/)) {
    m = substr(s, RSTART, RLENGTH)
    sub(/[.,;:!?]+$/, "", m)
    return m
  }
  return ""
}

function first_iso(s) {
  if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/))
    return substr(s, RSTART, RLENGTH)
  return ""
}

# A stamp line: a stamp keyword whose following window carries something
# date-shaped. Both halves are required — see the header note.
# "read" gets a tighter window than the explicit stamp verbs: it is an ordinary
# English verb, and at the wide window prose like "an unconfirmed read of a
# shipped build" became a candidate purely because a year appeared later in the
# sentence. check-stamps.sh carries the same two windows — one definition of
# what looks like a stamp, so the inventory and the check agree.
function is_stamp(line,   low, pos, rest, off, kw, wlen) {
  low = tolower(line)
  off = 0
  while (1) {
    if (!match(substr(low, off + 1), \
      /(^|[^a-z-])(verified|re-verified|docs-verified|last-verified|checked|confirmed|probed|measured|read|as[ -]of|current as of)([^a-z]|$)/))
      return 0
    pos = off + RSTART + RLENGTH - 1
    kw = substr(low, off + RSTART, RLENGTH)
    wlen = (kw ~ /read/) ? 30 : 60
    rest = substr(low, pos, wlen)
    if (rest ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 1
    if (rest ~ /[0-9]+\/[0-9]+\/[0-9]+/) return 1
    if (rest ~ /(19|20)[0-9][0-9]/) return 1
    if (rest ~ /(january|february|march|april|may|june|july|august|september|october|november|december)/) return 1
    if (rest ~ /(jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)[^a-z]/) return 1
    off = pos
    if (off >= length(low)) return 0
  }
}

function flush_fence() {
  if (!fence_open) return
  nf++
  f_url[nf] = fence_url
  f_date[nf] = fence_date
  f_start[nf] = fence_start
  f_end[nf] = fence_end
  fence_open = 0
}

function note_comment(start, end, text,   body, u) {
  # The comment delimiters are stripped before the closer test, so that
  # `<!-- /provenance -->` reads as a closer rather than as a line starting "<".
  body = text
  sub(/^[ \t]*<!--/, "", body)
  sub(/-->[ \t]*$/, "", body)
  body = trim(body)
  if (substr(body, 1, 1) == "/") {
    if (fence_open) { fence_end = end; flush_fence() }
    return
  }
  u = first_url(text)
  if (u == "") return
  flush_fence()
  fence_open = 1
  fence_url = u
  fence_date = first_iso(text)
  fence_start = start
  fence_end = end
}

function emit_file(   i, sep) {
  if (current == "") return
  flush_fence()
  if (emitted) printf(",\n")
  emitted = 1
  printf("      {\n")
  printf("        \"file\": \"%s\",\n", jesc(current))

  printf("        \"urls\": [")
  for (i = 1; i <= nu; i++) {
    sep = (i == 1) ? "\n" : ",\n"
    printf("%s          {\"url\": \"%s\", \"line\": %d, \"in_code_fence\": %s}", \
      sep, jesc(u_val[i]), u_line[i], u_fenced[i] ? "true" : "false")
  }
  printf("%s],\n", nu ? "\n        " : "")

  printf("        \"fences\": [")
  for (i = 1; i <= nf; i++) {
    sep = (i == 1) ? "\n" : ",\n"
    printf("%s          {\"source_url\": \"%s\", \"date\": %s, \"start_line\": %d, \"end_line\": %d}", \
      sep, jesc(f_url[i]), \
      f_date[i] == "" ? "null" : ("\"" jesc(f_date[i]) "\""), \
      f_start[i], f_end[i])
  }
  printf("%s],\n", nf ? "\n        " : "")

  printf("        \"stamp_lines\": [")
  for (i = 1; i <= ns; i++) {
    sep = (i == 1) ? "\n" : ",\n"
    printf("%s          {\"line\": %d, \"text\": \"%s\"}", sep, s_line[i], jesc(s_text[i]))
  }
  printf("%s],\n", ns ? "\n        " : "")

  printf("        \"quote_lines\": [")
  for (i = 1; i <= nq; i++) {
    sep = (i == 1) ? "\n" : ",\n"
    printf("%s          {\"line\": %d, \"kind\": \"%s\"}", sep, q_line[i], jesc(q_kind[i]))
  }
  printf("%s]\n", nq ? "\n        " : "")
  printf("      }")

  tot_urls += nu; tot_fences += nf; tot_stamps += ns; tot_quotes += nq
}

function reset_file(name) {
  current = name
  nu = 0; nf = 0; ns = 0; nq = 0
  delete u_val; delete u_line; delete u_fenced
  delete f_url; delete f_date; delete f_start; delete f_end
  delete s_line; delete s_text
  delete q_line; delete q_kind
  in_code = 0; in_comment = 0; fence_open = 0
  comment_text = ""; comment_start = 0
}

BEGIN { emitted = 0; current = "" }

FNR == 1 { emit_file(); reset_file(FILENAME) }

{
  line = $0

  if (in_comment) {
    comment_text = comment_text " " line
    if (line ~ /-->/) {
      note_comment(comment_start, FNR, comment_text)
      in_comment = 0
      comment_text = ""
    }
    next
  }

  if (line ~ /<!--/) {
    if (line ~ /-->/) {
      note_comment(FNR, FNR, line)
    } else {
      in_comment = 1
      comment_start = FNR
      comment_text = line
    }
    next
  }

  if (line ~ /^[ \t]*(```|~~~)/) { in_code = !in_code; next }

  if (!in_code && line ~ /^[ \t]*>/) {
    nq++; q_line[nq] = FNR; q_kind[nq] = "blockquote"
  }

  rest = line
  offset = 0
  while (match(rest, /https?:\/\/[^][ \t()<>"`{}]+/)) {
    url = substr(rest, RSTART, RLENGTH)
    sub(/[.,;:!?]+$/, "", url)
    nu++
    u_val[nu] = url; u_line[nu] = FNR; u_fenced[nu] = in_code
    offset = RSTART + RLENGTH
    rest = substr(rest, offset)
  }

  if (!in_code && is_stamp(line)) {
    ns++; s_line[ns] = FNR; s_text[ns] = trim(line)
  }
}

END {
  emit_file()
  printf("\n")
  printf("%d %d %d %d\n", tot_urls, tot_fences, tot_stamps, tot_quotes) > "/dev/stderr"
}
' "$@"
}

# --- JSON product ----------------------------------------------------------------

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

TOTALS_FILE="$(mktemp)"
trap 'rm -f "$TOTALS_FILE"' EXIT

total_files=0
total_urls=0
total_fences=0
total_stamps=0
total_quotes=0

printf '{\n'
printf '  "directories": ['
first_group=1
for d in ${GROUP_DIRS[@]+"${GROUP_DIRS[@]}"}; do
  members=()
  while IFS= read -r m; do
    [[ -n "$m" ]] && members+=("$m")
  done <<<"${GROUP_MEMBERS[$d]}"
  [[ "${#members[@]}" -eq 0 ]] && continue

  [[ "$first_group" -eq 1 ]] && printf '\n' || printf ',\n'
  first_group=0
  printf '    {\n'
  printf '      "dir": %s,\n' "$(json_str "$d")"
  printf '      "files": [\n'
  extract_group "${members[@]}" 2>"$TOTALS_FILE"
  printf '      ]\n'
  printf '    }'

  total_files=$((total_files + ${#members[@]}))
  read -r g_urls g_fences g_stamps g_quotes <"$TOTALS_FILE"
  total_urls=$((total_urls + g_urls))
  total_fences=$((total_fences + g_fences))
  total_stamps=$((total_stamps + g_stamps))
  total_quotes=$((total_quotes + g_quotes))
done
[[ "$first_group" -eq 1 ]] || printf '\n  '
printf '],\n'
printf '  "counts": {"directories": %s, "files": %s, "urls": %s, "fences": %s, "stamp_lines": %s, "quote_lines": %s}\n' \
  "${#GROUP_DIRS[@]}" "$total_files" "$total_urls" "$total_fences" "$total_stamps" "$total_quotes"
printf '}\n'
