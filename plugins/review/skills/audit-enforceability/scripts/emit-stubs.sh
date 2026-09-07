#!/usr/bin/env bash
# Write one enforcement-rung proposal stub per row of a conforming findings
# file, into a stub home the caller resolved.
#
#   emit-stubs.sh --findings <file> --classes <tsv> --out <dir> --scan-dir <dir>
#                 [--memory-root <dir>] [--dry-run]
#
# --findings   A conforming findings file: frontmatter declaring
#              `type: review-findings`, and a parseable `## Findings` table.
# --classes    TSV, one line per rank: rank<TAB>class<TAB>basis<TAB>rung<TAB>owner.
#              A path, or `-` to read it from stdin. A rank present in the table
#              but absent from the TSV still gets a stub, classed
#              `unclassified / unresolved / llm-only / none`. A rank present in
#              the TSV but absent from the table is a diagnostic, not a stub.
# --out        The resolved stub home. Created when absent.
# --scan-dir   The resolved reviews location the fix action scans for this
#              branch. Required. Never resolved here: both homes are the
#              caller's to resolve through its binding.
# --memory-root The root --out must sit UNDER. Optional, and the caller passes
#              it exactly when the caller COMPOSED --out from a root plus a
#              branch slug, which is the only case in which a segment of --out
#              is derived from the input file. A home handed over whole by the
#              consumer has no such segment and needs no anchor.
# --dry-run    Print the planned filenames and write nothing.
#
# THE PARSE RULE. Anchor on the `## Findings` heading, take the row table under
# it, and stop at the next `##` heading. Read nothing else. A conforming file
# re-renders every one of those rows under `## By dimension`, so a reader that
# scans the whole file for table rows counts each finding twice; that section is
# never read here. A `> DEGRADED:` blockquote above the heading is a coverage
# notice and is skipped with everything else outside the section. The table is
# located by its own header row rather than by a row-prefix pattern, the idiom
# scripts/check-detector-findings-crosswalk.sh uses, so a stray table elsewhere
# in the document can neither satisfy this parse nor be dragged into it.
#
# THE HOME FENCE. A stub must never be admitted by the fix action's merge set.
# That action scans the binding's resolved reviews location for `*.md` files
# whose frontmatter declares `type: review-findings`. A stub declares
# `type: enforceability-stub` and carries no `branch:` key, which is the
# load-bearing exclusion; the two refusals below are defense in depth. This
# script refuses, writing nothing, when --out is --scan-dir or sits under it,
# and when --out is the findings file's own directory or sits under it. Each
# path is normalized lexically and then folded to the filesystem's own spelling
# of its deepest EXISTING ancestor, so two spellings of one directory compare
# equal. Neither directory need exist, and nothing is created to decide a
# refusal: a refused run leaves the tree exactly as it found it.
#
# THE BRANCH SLUG IS NOT A PATH HERE. The findings file's `branch:` value is
# operator-supplied text: this script records it as `source-branch:` in the
# stub and never puts it, or anything else read out of the input, into a path.
# Every filename segment it derives is passed through the slug charset first.
# The caller does compose --out from a slug, so two further refusals bound
# that: a --out carrying a `..` segment is refused outright (no resolved home
# has one, and a slug that escaped sanitization is exactly how one appears),
# and --memory-root, when the caller composed --out, must contain it.
#
# Exit: 0 wrote (or planned) every stub; 2 usage, unreadable or non-conforming
# --findings, missing --scan-dir; 3 a refused home; 4 a written stub carried a
# forbidden findings-file marker (every stub this run wrote is removed first).
set -uo pipefail

usage() {
  printf 'usage: %s --findings <file> --classes <tsv|-> --out <dir> --scan-dir <dir> [--memory-root <dir>] [--dry-run]\n' \
    "${0##*/}" >&2
}

findings=""
classes=""
out=""
scan_dir=""
memory_root=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --findings)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    findings="$2"
    shift 2
    ;;
  --classes)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    classes="$2"
    shift 2
    ;;
  --out)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    out="$2"
    shift 2
    ;;
  --scan-dir)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    scan_dir="$2"
    shift 2
    ;;
  --memory-root)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    memory_root="$2"
    shift 2
    ;;
  --dry-run)
    dry_run=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    printf 'unknown argument: %s\n' "$1" >&2
    usage
    exit 2
    ;;
  esac
done

if [[ -z "$findings" ]]; then
  printf 'refusing: --findings names exactly one file, and none was given.\n' >&2
  exit 2
fi
if [[ -z "$out" ]]; then
  printf 'refusing: --out names the resolved stub home, and none was given.\n' >&2
  exit 2
fi
if [[ -z "$scan_dir" ]]; then
  printf 'refusing: --scan-dir names the reviews location the fix action scans; it is required so the stub home can be fenced out of it.\n' >&2
  exit 2
fi
if [[ ! -f "$findings" ]]; then
  printf 'refusing: --findings %s does not exist or is not a file.\n' "$findings" >&2
  exit 2
fi

# --- Lexical path normalization ------------------------------------------------
#
# Neither home need exist, so nothing here touches the filesystem and nothing is
# created to decide a refusal. Absolutize against $PWD, fold `\` to `/`, drop `.`
# and empty segments, pop on `..`, and drop a trailing slash. A drive-letter
# prefix is carried through so a Windows-style absolute path is not mistaken for
# a relative one. The result lands in NORM rather than on stdout: a command
# substitution is a subshell, and this script runs on hosts where a process
# spawn costs more than everything else it does.
NORM=""
normalize_path() {
  local p="$1" prefix="/" rest seg
  local -a stack=()
  p="${p//\\//}"
  if [[ "$p" =~ ^([A-Za-z]:)/ ]]; then
    prefix="${BASH_REMATCH[1]}/"
    p="${p:2}"
  elif [[ "$p" != /* ]]; then
    p="${PWD%/}/$p"
    p="${p//\\//}"
    if [[ "$p" =~ ^([A-Za-z]:)/ ]]; then
      prefix="${BASH_REMATCH[1]}/"
      p="${p:2}"
    fi
  fi
  rest="$p"
  while [[ -n "$rest" ]]; do
    seg="${rest%%/*}"
    if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
    case "$seg" in
    '' | '.') ;;
    '..')
      if [[ ${#stack[@]} -gt 0 ]]; then
        stack=("${stack[@]:0:${#stack[@]}-1}")
      fi
      ;;
    *) stack+=("$seg") ;;
    esac
  done
  local joined=""
  local s
  for s in ${stack[@]+"${stack[@]}"}; do
    joined="$joined$s/"
  done
  joined="${joined%/}"
  NORM="$prefix$joined"
}

# canonicalize_dir: fold NORM to the filesystem's own spelling of the deepest
# ancestor that exists, then re-attach the part that does not.
#
# Lexical normalization alone is not enough for the fence. One directory has
# more than one absolute spelling on a host whose shell layer maps drives
# (`/d/x` and `D:/x` and `d:/x` are one directory), and a symlinked home is a
# second spelling anywhere. Comparing two different spellings of the SAME
# directory reports "not within" and writes the stubs into the very directory
# the fence exists to protect.
#
# This reads the filesystem but still creates nothing: it walks UP to an
# existing ancestor rather than materializing the target, so a refused run
# leaves the tree exactly as it found it. When nothing resolves, the lexical
# value stands.
canonicalize_dir() {
  local p="$NORM" tail="" prev phys
  while [[ ! -d "$p" ]]; do
    prev="$p"
    tail="${p##*/}${tail:+/$tail}"
    p="${p%/*}"
    [[ -n "$p" ]] || p="/"
    [[ "$p" != "$prev" ]] || return 0
  done
  phys="$(cd -- "$p" 2>/dev/null && pwd -P)" || return 0
  [[ -n "$phys" ]] || return 0
  NORM="${phys%/}${tail:+/$tail}"
}

# is_within <candidate> <ancestor>: true when candidate IS ancestor or sits
# under it. The trailing slash is what keeps `reviews-archive` from reading as a
# child of `reviews`; stripping it off the ancestor first is what lets the
# filesystem root be an ancestor at all.
is_within() {
  local candidate="$1" ancestor="$2"
  [[ "$candidate" == "$ancestor" ]] && return 0
  [[ "$candidate" == "${ancestor%/}"/* ]]
}

# has_dotdot_segment <path>: true when the path AS GIVEN carries a `..`
# segment. Checked before normalization, which collapses `..` and would hide
# it. No home a binding resolves carries one, so its presence means a segment
# was pasted in raw, which is how an unsanitized slug escapes a tree.
has_dotdot_segment() {
  local p="${1//\\//}"
  [[ "$p" == ".." || "$p" == "../"* || "$p" == *"/.." || "$p" == *"/../"* ]]
}

# --- Findings-file admission, first half: the frontmatter marker --------------
#
# One pass over the frontmatter block reads both values this script needs: the
# `type:` marker that admits the file, and the `branch:` value every stub
# records as `source-branch:`. Frontmatter opens with `---` on line 1 and closes
# on the next `---`; content before an opening fence is not frontmatter.
declared_type=""
source_branch=""
fm_line=0
while IFS= read -r fm || [[ -n "$fm" ]]; do
  fm="${fm%$'\r'}"
  fm_line=$((fm_line + 1))
  if [[ $fm_line -eq 1 ]]; then
    [[ "$fm" == "---" ]] || break
    continue
  fi
  [[ "$fm" == "---" ]] && break
  case "$fm" in
  'type:'*)
    declared_type="${fm#type:}"
    declared_type="${declared_type#"${declared_type%%[![:space:]]*}"}"
    declared_type="${declared_type%"${declared_type##*[![:space:]]}"}"
    ;;
  'branch:'*)
    source_branch="${fm#branch:}"
    source_branch="${source_branch#"${source_branch%%[![:space:]]*}"}"
    source_branch="${source_branch%"${source_branch##*[![:space:]]}"}"
    ;;
  *) ;;
  esac
done <"$findings"

if [[ "$declared_type" != "review-findings" ]]; then
  printf 'refusing: %s does not declare "type: review-findings" in its frontmatter.\n' "$findings" >&2
  exit 2
fi
[[ -n "$source_branch" ]] || source_branch="unstated"

# --- Findings-file admission, second half: the table must parse ---------------
#
# The section-anchored table reader. Emits one NUL-free record per row, cells
# separated by \002, with escaped pipes restored.
read_rows() {
  awk '
    BEGIN { in_section = 0; seen_header = 0; expect_sep = 0 }
    { sub(/\r$/, "") }
    /^## Findings[ \t]*$/ { in_section = 1; next }
    in_section && /^##/ { in_section = 0; next }
    !in_section { next }
    /^[ \t]*$/ { next }
    $0 !~ /^[ \t]*\|/ { next }
    {
      line = $0
      gsub(/\\[|]/, "\001", line)
      n = split(line, cell, "|")
      for (i = 1; i <= n; i++) {
        gsub(/\001/, "|", cell[i])
        gsub(/^[ \t]+|[ \t]+$/, "", cell[i])
      }
      if (!seen_header) {
        if (n == 9 && cell[2] == "Rank" && cell[3] == "Tier" && cell[4] == "Confidence" &&
            cell[5] == "Location" && cell[6] == "Surface(s)" && cell[7] == "Finding" &&
            cell[8] == "Action") {
          seen_header = 1
          expect_sep = 1
        }
        next
      }
      if (expect_sep) { expect_sep = 0; next }
      if (n != 9) {
        printf "diagnostic: row %d of the ## Findings table splits into %d fields, not 9; an unescaped pipe shifts its cells, so it was not stubbed. Write a literal pipe as \\|.\n", NR, n > "/dev/stderr"
        malformed++
        next
      }
      printf "%s\002%s\002%s\002%s\002%s\002%s\002%s\n", cell[2], cell[3], cell[4], cell[5], cell[6], cell[7], cell[8]
    }
    END {
      if (!seen_header) exit 9
      # A trailing sentinel record, so the shell can report a row this reader
      # had to drop instead of printing a count that silently excludes it.
      printf "\003%d\n", malformed
    }
  ' "$findings"
}

rows_raw="$(read_rows)"
rows_status=$?
if [[ $rows_status -eq 9 ]]; then
  printf 'refusing: %s has no parseable "## Findings" table (no row-table header under the heading).\n' "$findings" >&2
  exit 2
fi
if [[ $rows_status -ne 0 ]]; then
  printf 'refusing: could not read the "## Findings" table in %s.\n' "$findings" >&2
  exit 2
fi

# --- The home fences -----------------------------------------------------------

if has_dotdot_segment "$out"; then
  printf 'refusing: the stub home %s carries a ".." segment. No home a binding resolves carries one, and a branch slug that reached the path unsanitized is how one appears; sanitize the slug rather than letting it steer the path.\n' \
    "$out" >&2
  exit 3
fi
if has_dotdot_segment "$scan_dir"; then
  printf 'refusing: the scan directory %s carries a ".." segment, so the fence would be compared against a directory the caller did not name.\n' \
    "$scan_dir" >&2
  exit 3
fi

normalize_path "$out"
canonicalize_dir
out_abs="$NORM"
normalize_path "$scan_dir"
canonicalize_dir
scan_abs="$NORM"
normalize_path "$findings"
findings_abs="$NORM"
findings_dir_abs="${findings_abs%/*}"
[[ -n "$findings_dir_abs" ]] || findings_dir_abs="/"
NORM="$findings_dir_abs"
canonicalize_dir
findings_dir_abs="$NORM"

if is_within "$out_abs" "$scan_abs"; then
  printf 'refusing: the stub home %s is the fix action scan directory %s or sits under it; a stub written there is offered to the fix pass.\n' \
    "$out_abs" "$scan_abs" >&2
  exit 3
fi
if is_within "$out_abs" "$findings_dir_abs"; then
  printf 'refusing: the stub home %s is the findings file directory %s or sits under it; that directory is a findings home, not a stub home.\n' \
    "$out_abs" "$findings_dir_abs" >&2
  exit 3
fi

# The anchor. Supplied exactly when the caller COMPOSED --out from a root plus
# a branch slug, so it is the one check that bounds where a composed path may
# land rather than only which two siblings it may not be.
if [[ -n "$memory_root" ]]; then
  if has_dotdot_segment "$memory_root"; then
    printf 'refusing: the memory root %s carries a ".." segment.\n' "$memory_root" >&2
    exit 3
  fi
  normalize_path "$memory_root"
  canonicalize_dir
  root_abs="$NORM"
  if [[ "$out_abs" == "$root_abs" ]]; then
    printf 'refusing: the stub home %s IS the memory root; a concern directory sits under the root, never at it.\n' \
      "$out_abs" >&2
    exit 3
  fi
  if ! is_within "$out_abs" "$root_abs"; then
    printf 'refusing: the stub home %s does not sit under the memory root %s. A composed home escaped the tree it was composed from.\n' \
      "$out_abs" "$root_abs" >&2
    exit 3
  fi
fi

# --- Classification input ------------------------------------------------------

declare -A class_of basis_of rung_of owner_of seen_rank

read_classes() {
  local c_rank c_class c_basis c_rung c_owner
  while IFS=$'\t' read -r c_rank c_class c_basis c_rung c_owner || [[ -n "$c_rank" ]]; do
    c_rank="${c_rank%$'\r'}"
    c_owner="${c_owner%$'\r'}"
    [[ -n "$c_rank" ]] || continue
    class_of["$c_rank"]="$c_class"
    basis_of["$c_rank"]="$c_basis"
    rung_of["$c_rank"]="$c_rung"
    owner_of["$c_rank"]="$c_owner"
  done
}

if [[ -n "$classes" ]]; then
  if [[ "$classes" == "-" ]]; then
    read_classes
  elif [[ -f "$classes" ]]; then
    read_classes <"$classes"
  else
    printf 'refusing: --classes %s does not exist; pass a readable TSV or "-" for stdin.\n' "$classes" >&2
    exit 2
  fi
fi

# --- Derived stub values -------------------------------------------------------

source_name="${findings_abs##*/}"
now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

digest="unavailable"
digest_line=""
if command -v sha256sum >/dev/null 2>&1; then
  digest_line="$(sha256sum "$findings")"
elif command -v shasum >/dev/null 2>&1; then
  digest_line="$(shasum -a 256 "$findings")"
elif command -v openssl >/dev/null 2>&1; then
  digest_line="$(openssl dgst -r -sha256 "$findings")"
fi
if [[ -n "$digest_line" ]]; then
  digest="${digest_line:0:12}"
fi

# sanitize_slug <text>: lowercase, every character outside [a-z0-9._-] replaced
# by `-`, truncated to 40 characters. Result lands in SLUG. Fork-free on
# purpose: this runs several times per row, and a spawn-bound shell pays for
# every subprocess.
SLUG=""
sanitize_slug() {
  local raw="${1,,}" out="" rest ch
  local allowed='abcdefghijklmnopqrstuvwxyz0123456789._-'
  rest="$raw"
  while [[ -n "$rest" ]]; do
    ch="${rest:0:1}"
    rest="${rest:1}"
    if [[ "$allowed" == *"$ch"* ]]; then out="$out$ch"; else out="$out-"; fi
  done
  out="${out:0:40}"
  [[ -n "$out" ]] || out="unlocated"
  SLUG="$out"
}

# --- Plan, then write ----------------------------------------------------------

declare -a written=()
declare -a table_ranks=()
count=0
malformed=0

mkdir_done=0

while IFS= read -r record; do
  [[ -n "$record" ]] || continue
  if [[ "$record" == $'\003'* ]]; then
    malformed="${record#$'\003'}"
    continue
  fi
  IFS=$'\002' read -r r_rank r_tier r_conf r_loc r_surf r_find r_act <<<"$record"
  table_ranks+=("$r_rank")
  seen_rank["$r_rank"]=1

  f_class="${class_of[$r_rank]:-unclassified}"
  f_basis="${basis_of[$r_rank]:-unresolved}"
  f_rung="${rung_of[$r_rank]:-llm-only}"
  f_owner="${owner_of[$r_rank]:-none}"
  [[ -n "$f_class" ]] || f_class="unclassified"
  [[ -n "$f_basis" ]] || f_basis="unresolved"
  [[ -n "$f_rung" ]] || f_rung="llm-only"
  [[ -n "$f_owner" ]] || f_owner="none"

  if [[ "$r_rank" =~ ^[0-9]+$ ]]; then
    printf -v rank_seg '%02d' "$((10#$r_rank))"
  else
    sanitize_slug "$r_rank"
    rank_seg="$SLUG"
  fi
  sanitize_slug "$r_loc"
  slug="$SLUG"
  sanitize_slug "$f_rung"
  base="$rank_seg-$SLUG-$slug"

  target="$out/$base.md"
  if [[ $dry_run -eq 0 ]]; then
    suffix=2
    while [[ -e "$target" ]]; do
      target="$out/$base-$suffix.md"
      suffix=$((suffix + 1))
    done
  fi

  count=$((count + 1))

  if [[ $dry_run -eq 1 ]]; then
    printf '%s\n' "$target"
    continue
  fi

  if [[ $mkdir_done -eq 0 ]]; then
    if ! mkdir -p "$out"; then
      printf 'refusing: could not create the stub home %s.\n' "$out" >&2
      exit 2
    fi
    mkdir_done=1
  fi

  # A write that fails part way leaves a truncated stub the self-check below
  # would read as clean, so the status is checked rather than assumed.
  if ! {
    printf -- '---\n'
    printf 'type: enforceability-stub\n'
    printf 'date: %s\n' "$now_utc"
    printf 'source-findings: %s\n' "$source_name"
    printf 'source-sha256: %s\n' "$digest"
    printf 'source-branch: %s\n' "$source_branch"
    printf 'rank: %s\n' "$r_rank"
    printf 'finding-class: %s\n' "$f_class"
    printf 'class-basis: %s\n' "$f_basis"
    printf 'rung: %s\n' "$f_rung"
    printf 'owner: %s\n' "$f_owner"
    printf -- '---\n'
    printf '\n## Finding\n\n'
    printf -- '- Location: %s\n' "$r_loc"
    printf -- '- Tier: %s\n' "$r_tier"
    printf -- '- Confidence: %s\n' "$r_conf"
    printf -- '- Surface(s): %s\n' "$r_surf"
    printf -- '- Finding: %s\n' "$r_find"
    printf -- '- Action: %s\n' "$r_act"
    printf '\n## Proposed rung\n\n'
    # The backticks belong to the markdown this writes, not to the shell.
    # shellcheck disable=SC2016
    printf 'Rung `%s`, reached from finding class `%s` on basis `%s`. The check this rung would carry asserts the class at that rung, so the finding stops being re-derived by a reader on every review. Owner or pointer: %s.\n' \
      "$f_rung" "$f_class" "$f_basis" "$f_owner"
    printf '\n## Next step\n\n'
    printf '%s\n' "$f_owner"
    printf '\n## Not done here\n\n'
    printf 'This stub proposes. Nothing was implemented.\n'
  } >"$target"; then
    rm -f "$target" ${written[@]+"${written[@]}"}
    printf 'refusing: writing %s failed part way; every stub this run wrote has been removed.\n' "$target" >&2
    exit 2
  fi

  written+=("$target")
done <<<"$rows_raw"

for c_rank in "${!class_of[@]}"; do
  if [[ -z "${seen_rank[$c_rank]:-}" ]]; then
    printf 'diagnostic: --classes names rank %s, which the "## Findings" table does not carry; no stub written for it.\n' \
      "$c_rank" >&2
  fi
done

if [[ $dry_run -eq 1 ]]; then
  printf '%d findings planned, 0 stubs written (dry run) in %s\n' "$count" "$out"
  exit 0
fi

# --- Post-write self-check -----------------------------------------------------
#
# The stub shape carries none of these markers, but a value that reached a stub
# from the findings file or from --classes could. A stub that carries one is
# admissible to the fix action's merge set, which is the one outcome this script
# exists to make impossible: refuse, and take back every stub this run wrote.
# has_forbidden_marker <file>: true when any LINE of the file starts with one of
# the four markers. Read in-shell rather than with grep: the markers are
# line-anchored literals, and a spawn per stub is the dominant cost on a
# spawn-bound host.
has_forbidden_marker() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
    'type: review-findings'* | 'type: fix-pass-record'* | 'branch:'* | '## Findings'*)
      return 0
      ;;
    *) ;;
    esac
  done <"$1"
  return 1
}

violation=""
for path in ${written[@]+"${written[@]}"}; do
  if has_forbidden_marker "$path"; then
    violation="$path"
    break
  fi
done

if [[ -n "$violation" ]]; then
  rm -f ${written[@]+"${written[@]}"}
  printf 'refusing: %s carried a findings-file marker, which would offer it to the fix pass. Every stub this run wrote has been removed.\n' \
    "$violation" >&2
  exit 4
fi

printf '%d findings → %d stubs in %s\n' "$count" "${#written[@]}" "$out"
if [[ "$malformed" -gt 0 ]]; then
  printf 'WARNING: %d further row(s) carried an unescaped pipe and were NOT stubbed; the count above excludes them.\n' \
    "$malformed" >&2
fi
exit 0
