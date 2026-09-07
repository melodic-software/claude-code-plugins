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
# `type: enforceability-stub`, and THAT marker is the load-bearing exclusion:
# the merge set is keyed on `type:`, so a stub is excluded by declaring the
# wrong one. The absent `branch:` key is the weaker clause and is not what
# excludes: an unanchored `branch:` search matches every stub anyway, through
# the `source-branch:` key each one carries. The refusals below are defense in
# depth. This script refuses, writing nothing, when --out is --scan-dir or sits
# under it, and when --out is the findings file's own directory or sits under
# it. Each path is normalized lexically and then folded to the filesystem's own
# spelling of its deepest EXISTING ancestor, so two spellings of one directory
# compare equal. Nothing is created to decide a refusal: a refused run leaves
# the tree exactly as it found it. Neither directory need exist, but existence
# decides WHO answers. For the part of a chain that exists the filesystem
# answers, by device and inode. For the unresolved tail, a spelling fold
# answers, and that fold is deliberately coarser than the CASE fold of any
# filesystem this runs on, so the absent case is refused wherever it might be
# one directory (it is not coarser than a Unicode NORMALIZATION fold, which
# APFS and HFS+ apply and NTFS does not; two normalizations of one name still
# compare unequal there). The inode walk never takes a refusal away once the
# fold has spoken for a tail, and it never lets the fold speak for inodes the
# filesystem can already distinguish.
#
# THE BRANCH SLUG IS NOT A PATH HERE. The findings file's `branch:` value is
# operator-supplied text: this script records it as `source-branch:` in the
# stub and never puts it, or anything else read out of the input, into a path.
# Every filename segment it derives is passed through the slug charset first.
# The caller does compose --out from a slug, so three further refusals bound
# that: a --out carrying a `..` segment is refused outright (no resolved home
# has one, and a slug that escaped sanitization is exactly how one appears);
# --memory-root, when the caller composed --out, must contain it; and the last
# path segment of --out (the branch slug) must match the slug charset
# [a-z0-9._-], so an unsanitized value that does not rely on `..` still cannot
# steer the home.
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
memory_root_given=0
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
    memory_root_given=1
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
# An EMPTY --memory-root is a caller whose root variable did not expand, not a
# caller who chose not to anchor. Treating it as "not supplied" would turn the
# anchor off exactly when the composition it guards went wrong.
if [[ $memory_root_given -eq 1 && -z "$memory_root" ]]; then
  printf 'refusing: --memory-root was given but is empty. Omit the flag to state that the home was not composed here; an empty value is an unexpanded variable, not a decision.\n' >&2
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
  # A root path renders as its prefix, never as the empty string: an empty
  # ancestor turns every diagnostic that names it into a blank.
  [[ -n "$NORM" ]] || NORM="/"
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
    # A bare drive prefix is not a directory to test; its ROOT is. Without this
    # a drive-letter path whose whole chain is absent never folds, while its
    # other spelling does, and the two never compare equal.
    [[ "$p" =~ ^[A-Za-z]:$ ]] && p="$p/"
    [[ -n "$p" ]] || p="/"
    [[ "$p" != "$prev" ]] || return 0
  done
  phys="$(cd -- "$p" 2>/dev/null && pwd -P)" || return 0
  [[ -n "$phys" ]] || return 0
  if [[ -z "$tail" ]]; then
    NORM="$phys"
  else
    NORM="${phys%/}/$tail"
  fi
}

# is_within <candidate> <ancestor>: true when candidate IS ancestor or sits
# under it. The trailing slash is what keeps `reviews-archive` from reading as a
# child of `reviews`; stripping it off the ancestor first is what lets the
# filesystem root be an ancestor at all.
# is_within <candidate> <ancestor>: comparison is CASE-INSENSITIVE, and that is
# the fail-closed direction rather than an assumption about the filesystem. On a
# case-insensitive volume `.../REVIEWS` and `.../reviews` are one directory that
# a case-sensitive compare calls two, which writes stubs into the very directory
# the fence protects; `pwd -P` does not fold segment case, so canonicalization
# cannot close it. On a case-sensitive volume the cost is the opposite error, a
# refusal of a genuinely distinct sibling that differs only in case, which the
# operator sees and can rename around. A visible false refusal is recoverable;
# a silent write into the fix action's scan directory is not.
# A string compare cannot settle it alone. `nocasematch` folds ASCII only when
# no locale is set, which is the common state, while the filesystem folds all of
# Unicode: `RÉVIEWS` and `réviews` are then one directory that the string
# compare calls two. So the string compare is the FAST PATH, and a walk that
# asks the filesystem itself (`-ef`, which compares device and inode rather than
# spelling) is the authority for the part of the path that exists.
#
# THIS PREDICATE IS THE STRICT ONE, and it stays strict. Past the fast path
# above (an exact or ASCII-case spelling still answers "within" without asking
# the filesystem anything), it answers "not within" whenever the filesystem
# cannot settle the question, which is the fail-closed direction for the two
# --memory-root checks, its only remaining callers: a composed home whose root
# is absent must not be admitted on a NON-ASCII spelling match. The two home
# fences want the opposite default, since for them a positive answer is a
# refusal, and they call may_be_within below instead.
is_within() {
  local candidate="$1" ancestor="$2" had_nocase=0 rc=1 probe prev
  shopt -q nocasematch && had_nocase=1
  shopt -s nocasematch
  if [[ "$candidate" == "$ancestor" || "$candidate" == "${ancestor%/}"/* ]]; then
    rc=0
  fi
  [[ $had_nocase -eq 1 ]] || shopt -u nocasematch
  [[ $rc -eq 0 ]] && return 0

  # The filesystem's own answer, for the existing part of the chain. Walks UP
  # from the candidate, so nothing is created to decide it.
  [[ -e "$ancestor" ]] || return 1
  probe="$candidate"
  while :; do
    if [[ -e "$probe" ]] && [[ "$probe" -ef "$ancestor" ]]; then
      return 0
    fi
    prev="$probe"
    probe="${probe%/*}"
    [[ "$probe" =~ ^[A-Za-z]:$ ]] && probe="$probe/"
    [[ -n "$probe" ]] || probe="/"
    [[ "$probe" != "$prev" ]] || return 1
  done
}

# fold_ascii_case <path>: ASCII letters to upper case; every other character
# stands. Result in ASCII_FOLDED. This is the fence's ASCII fast path: it
# matches `reviews` / `REVIEWS` without asking the filesystem, and it does not
# match `réviews` / `RÉVIEWS` even when the locale's case table would, so those
# pairs reach the inode walk. `nocasematch` is not used: a UTF-8 locale folds
# Unicode case too.
ASCII_FOLDED=""
fold_ascii_case() {
  local rest="$1" ch head out=""
  local lower='abcdefghijklmnopqrstuvwxyz'
  local upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  while [[ -n "$rest" ]]; do
    ch="${rest:0:1}"
    rest="${rest:1}"
    head="${lower%%"$ch"*}"
    if [[ "$head" != "$lower" ]]; then
      out="$out${upper:${#head}:1}"
    else
      out="$out$ch"
    fi
  done
  ASCII_FOLDED="$out"
}

# fold_path <path>: the spelling-insensitive rendering the fences compare when
# the filesystem cannot answer. ASCII letters fold to upper case; every other
# ASCII character stands; a RUN of anything else folds to one placeholder.
# Result in FOLDED rather than on stdout: same spawn-avoidance as
# normalize_path.
#
# The fold is deliberately COARSER than any filesystem's CASE fold, and that is
# the whole design. It is not coarser than a Unicode NORMALIZATION fold: APFS
# and HFS+ treat NFC and NFD spellings of one name as one directory, and this
# fold does not, so on those filesystems that pair is left to the `-ef` arm.
# A fold that tried to match NTFS character for character would need
# NTFS's upcase table; a fold that used `nocasematch` or `${p,,}` would inherit
# whatever the ambient locale happens to be, which is the hole this closes. So
# instead of asking which non-ASCII characters a filesystem folds together, this
# treats every one of them as indistinguishable from every other, and from a run
# of them. `réviews` and `RÉVIEWS` fold alike, which is the point; so do
# `révu` and `rêvu`, which is the cost. That cost is a VISIBLE refusal of two
# genuinely distinct non-ASCII siblings, recoverable by renaming one, and it is
# paid only where the filesystem cannot answer: an unresolved tail after the
# inode walk has matched the existing prefix. Two siblings that already exist
# as distinct inodes are not folded together; the walk sees they are different
# directories and the fold never runs on them. The opposite error, a silent
# write into the fix action's scan directory, is not recoverable, and it is
# the error an ASCII-only compare of an ABSENT tail actually made.
FOLDED=""
fold_path() {
  local rest="$1" ch head out=""
  local lower='abcdefghijklmnopqrstuvwxyz'
  local upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  # Every ASCII character that stands as itself. Anything absent from both this
  # and the lower-case set is what the placeholder covers, control characters
  # included: they are unaddressable in a path and folding them together is the
  # same fail-closed direction.
  local kept='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !"#$%&'"'"'()*+,-./:;<=>?@[\]^_`{|}~'
  while [[ -n "$rest" ]]; do
    ch="${rest:0:1}"
    rest="${rest:1}"
    head="${lower%%"$ch"*}"
    if [[ "$head" != "$lower" ]]; then
      out="$out${upper:${#head}:1}"
      continue
    fi
    head="${kept%%"$ch"*}"
    if [[ "$head" != "$kept" ]]; then
      out="$out$ch"
      continue
    fi
    # Collapsing a RUN rather than emitting one placeholder per character is
    # what makes this independent of how the shell slices the string: a UTF-8
    # locale yields one character where the C locale yields two bytes, and both
    # land on the same placeholder.
    [[ "$out" == *$'\001' ]] || out="$out"$'\001'
  done
  FOLDED="$out"
}

# split_existing <path>: SPLIT_BASE gets the deepest ancestor of <path> that
# exists (the path itself when it does), SPLIT_TAIL the segments below it.
# Walks UP only, so nothing is created to decide it.
SPLIT_BASE=""
SPLIT_TAIL=""
split_existing() {
  local p="$1" tail="" prev
  while [[ ! -e "$p" ]]; do
    prev="$p"
    tail="${p##*/}${tail:+/$tail}"
    p="${p%/*}"
    [[ "$p" =~ ^[A-Za-z]:$ ]] && p="$p/"
    [[ -n "$p" ]] || p="/"
    if [[ "$p" == "$prev" ]]; then
      SPLIT_BASE=""
      SPLIT_TAIL=""
      return 1
    fi
  done
  SPLIT_BASE="$p"
  SPLIT_TAIL="$tail"
}

# may_be_within <candidate> <ancestor>: the FENCE predicate. True when the
# candidate is the ancestor, sits under it, or might be either. Where is_within
# answers "no" on anything the filesystem cannot settle, this answers "yes",
# because here a positive answer is a refusal and the unsettled case is exactly
# the one that must not be written into.
#
# Three arms, all fail-closed, none creating anything. Existence decides
# which of the last two answers; the first is an ASCII-letter fold that does
# not inherit the locale:
#
#   1. Exact or ASCII-case spelling. `reviews` and `REVIEWS` refuse without
#      asking the filesystem, which is the documented cost case 17 asserts on
#      both kinds of volume. Unlike `nocasematch`, this fold does not take the
#      locale's Unicode case table, so `réviews` / `RÉVIEWS` do not match here
#      and fall through to the inode walk.
#   2. The filesystem, generalized past the "ancestor exists" gate is_within
#      stops at. The ancestor is split at its deepest EXISTING ancestor; the
#      candidate is walked up to a prefix that IS that directory by device and
#      inode. When the ancestor exists whole, its tail is empty and this
#      reduces to the walk is_within already does: distinct existing inodes
#      are not one directory, even if a later fold would have spelled them
#      alike.
#   3. What is left of each path after that match, which by construction
#      exists on neither side, is settled by the fold. That is the only arm
#      that pays the coarse-fold over-refusal (`révu` vs `rêvu` as tails).
may_be_within() {
  local candidate="$1" ancestor="$2" tail="" probe prev
  local c_folded a_folded a_base a_tail c_ascii a_ascii
  fold_ascii_case "$candidate"
  c_ascii="$ASCII_FOLDED"
  fold_ascii_case "$ancestor"
  a_ascii="$ASCII_FOLDED"
  if [[ "$c_ascii" == "$a_ascii" || "$c_ascii" == "${a_ascii%/}"/* ]]; then
    return 0
  fi

  split_existing "$ancestor" || return 1
  a_base="$SPLIT_BASE"
  a_tail="$SPLIT_TAIL"
  fold_path "$a_tail"
  a_folded="$FOLDED"
  probe="$candidate"
  while :; do
    if [[ -e "$probe" ]] && [[ "$probe" -ef "$a_base" ]]; then
      [[ -n "$a_tail" ]] || return 0
      fold_path "$tail"
      c_folded="$FOLDED"
      [[ "$c_folded" == "$a_folded" || "$c_folded" == "${a_folded%/}/"* ]]
      return $?
    fi
    prev="$probe"
    tail="${probe##*/}${tail:+/$tail}"
    probe="${probe%/*}"
    [[ "$probe" =~ ^[A-Za-z]:$ ]] && probe="$probe/"
    [[ -n "$probe" ]] || probe="/"
    [[ "$probe" != "$prev" ]] || return 1
  done
}

# has_dotdot_segment <path>: true when the path AS GIVEN carries a `..`
# segment. Checked before normalization, which collapses `..` and would hide
# it. No home a binding resolves carries one, so its presence means a segment
# was pasted in raw, which is how an unsanitized slug escapes a tree.
has_dotdot_segment() {
  local p="${1//\\//}"
  [[ "$p" == ".." || "$p" == "../"* || "$p" == *"/.." || "$p" == *"/../"* ]] && return 0
  # A trailing `.` names the parent as the home. No binding resolves one, and a
  # slug of `.` that survived the charset rule is how it appears.
  [[ "$p" == "." || "$p" == *"/." ]]
}

# has_unaddressable_segment <dir>: true when a segment ends in a dot or a space.
# Such a directory exists but Win32 path APIs cannot address it, so a stub home
# there is invisible to every consumer that is not this shell; it also compares
# unequal to the same name without the suffix, which is how it slips a fence.
# Directory arguments only: a file name legitimately ends in `.md`.
has_unaddressable_segment() {
  local p="${1//\\//}" seg rest
  rest="$p"
  while [[ -n "$rest" ]]; do
    seg="${rest%%/*}"
    if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
    [[ -z "$seg" || "$seg" == "." || "$seg" == ".." ]] && continue
    [[ "$seg" == *[.\ ] ]] && return 0
  done
  return 1
}

# is_unc_path <path>: true for a path whose leading double separator makes it a
# network share. The lexical normalizer collapses the empty segment, so the
# fence would compare a path that does not exist while the OS still resolves the
# RAW argument back to a real directory, possibly inside a fenced one. Refused
# rather than reasoned about: no binding resolves a share this way.
is_unc_path() {
  local p="${1//\\//}"
  [[ "$p" == //* ]]
}

# last_path_segment <path>: the final component after folding `\` and dropping
# trailing slashes. For a composed home that is the branch slug; for a
# handed-over home it is still the last segment the caller named. Result in
# LAST_SEG rather than on stdout: same spawn-avoidance as normalize_path.
LAST_SEG=""
last_path_segment() {
  local p="${1//\\//}"
  while [[ "$p" == */ ]]; do
    p="${p%/}"
  done
  LAST_SEG="${p##*/}"
}

# is_slug_charset <seg>: true when every character is in the branch-slug
# charset [a-z0-9._-]. Empty is a miss. `.` and `..` match the class
# syntactically and are refused by has_dotdot_segment instead; this check is
# the other half: an unsanitized slug that does not use `..` to escape.
is_slug_charset() {
  local slug_re='^[a-z0-9._-]+$'
  [[ -n "$1" && "$1" =~ $slug_re ]]
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
# The input path is fenced for the same reason, and it is the subtler case: a
# `..` after a symlinked segment resolves one way for the OS and another way
# for the lexical normalizer, so the directory this script fences against would
# not be the directory the file actually sits in.
if has_dotdot_segment "$findings"; then
  printf 'refusing: the findings path %s carries a ".." or "." segment, so the directory fenced against would not be the one the file sits in. Name the file by a path with neither in it.\n' \
    "$findings" >&2
  exit 3
fi
for dir_candidate in "$out" "$scan_dir" ${memory_root:+"$memory_root"}; do
  if has_unaddressable_segment "$dir_candidate"; then
    printf 'refusing: %s has a path segment ending in a dot or a space. That directory exists but is unaddressable by ordinary path APIs, so a stub home there is invisible to every consumer, and it compares unequal to the same name without the suffix.\n' \
      "$dir_candidate" >&2
    exit 3
  fi
done
for unc_candidate in "$out" "$scan_dir" "$findings" ${memory_root:+"$memory_root"}; do
  if is_unc_path "$unc_candidate"; then
    printf 'refusing: %s is a network-share path. The fence normalizes it to a path that does not exist while the operating system still resolves the raw argument, so the two would not describe the same directory.\n' \
      "$unc_candidate" >&2
    exit 3
  fi
done

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
# A file directly under a drive root leaves a bare drive prefix, which names no
# directory; its root does.
[[ "$findings_dir_abs" =~ ^[A-Za-z]:$ ]] && findings_dir_abs="$findings_dir_abs/"
NORM="$findings_dir_abs"
canonicalize_dir
findings_dir_abs="$NORM"

if may_be_within "$out_abs" "$scan_abs"; then
  printf 'refusing: the stub home %s is the fix action scan directory %s or sits under it; a stub written there is offered to the fix pass.\n' \
    "$out_abs" "$scan_abs" >&2
  exit 3
fi
if may_be_within "$out_abs" "$findings_dir_abs"; then
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
  if is_within "$root_abs" "$out_abs"; then
    printf 'refusing: the stub home %s IS the memory root, or holds it; a concern directory sits under the root, never at or above it.\n' \
      "$out_abs" >&2
    exit 3
  fi
  if ! is_within "$out_abs" "$root_abs"; then
    printf 'refusing: the stub home %s does not sit under the memory root %s. A composed home escaped the tree it was composed from.\n' \
      "$out_abs" "$root_abs" >&2
    exit 3
  fi
fi

# The last path segment is the branch slug the caller composed from
# operator-supplied frontmatter (or the last segment of a handed-over home).
# --memory-root bounds WHERE the home may sit; this bounds WHAT that last
# segment may be, including when the caller omitted the anchor. A charset
# miss is an unsanitized value reaching the path.
last_path_segment "$out"
if ! is_slug_charset "$LAST_SEG"; then
  printf 'refusing: the stub home %s has a last path segment outside the branch-slug charset [a-z0-9._-]. That segment is the branch slug the caller composed from operator-supplied frontmatter; a value that reached the path unsanitized is how a write escapes the tree. Apply the slug rule rather than letting the raw value steer the path.\n' \
    "$out" >&2
  exit 3
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
# Every directory level `mkdir -p` will create, deepest first, and only those:
# the rollback below removes exactly this list. A level that already existed is
# never recorded, so a home the caller had prepared survives a refusal.
declare -a created_dirs=()

while IFS= read -r record; do
  [[ -n "$record" ]] || continue
  if [[ "$record" == $'\003'* ]]; then
    malformed="${record#$'\003'}"
    continue
  fi
  IFS=$'\002' read -r r_rank r_tier r_conf r_loc r_surf r_find r_act <<<"$record"
  # An empty Rank cell is a row, not a reason to lose one. It cannot key the
  # classification map (an empty array subscript is an error that would drop the
  # row while the summary still counted only what it wrote), so it takes a
  # placeholder and falls through to the unclassified defaults.
  [[ -n "$r_rank" ]] || r_rank="unranked"
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
    # `mkdir -p` creates every absent level, not just the innermost, so every
    # absent level is recorded. The walk starts from the NORMALIZED home, not
    # the raw argument: `${p%/*}` on a raw `--out` reads a trailing slash as one
    # more level (recording the same directory twice, so the rollback hits
    # ENOENT on the duplicate and stops before the parent) and reads a `.`
    # segment as a level that already exists (stopping the walk at once). Both
    # spell the same home as the plain form, which rolls back correctly.
    # Normalizing also keeps the Windows-style `\` form reading as many
    # segments rather than one.
    mk_probe="$out_abs"
    while [[ ! -d "$mk_probe" ]]; do
      created_dirs+=("$mk_probe")
      mk_prev="$mk_probe"
      mk_probe="${mk_probe%/*}"
      [[ "$mk_probe" =~ ^[A-Za-z]:$ ]] && mk_probe="$mk_probe/"
      [[ -n "$mk_probe" ]] || mk_probe="/"
      [[ "$mk_probe" != "$mk_prev" ]] || break
    done
    if ! mkdir -p "$out"; then
      printf 'refusing: could not create the stub home %s.\n' "$out" >&2
      exit 2
    fi
    mkdir_done=1
  fi

  # A write that fails part way leaves a truncated or absent stub the
  # self-check below would read as clean, so the status is checked rather than
  # assumed. The status is captured on its own line: `if ! { ...; } >FILE`
  # returns 0 when it is the REDIRECTION that failed, so the negated form reads
  # a failed write as a success.
  {
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
  } >"$target"
  write_status=$?
  if [[ $write_status -ne 0 ]]; then
    rm -f -- "$target" ${written[@]+"${written[@]}"}
    printf 'refusing: writing %s failed (status %d); every stub this run wrote has been removed.\n' \
      "$target" "$write_status" >&2
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
# The line model is deliberately WIDER than this script's own writer uses. A
# reader downstream may split on a bare CR as well as LF (every
# universal-newline reader does), and may tolerate leading whitespace before a
# key. A check that modelled only LF-terminated, column-0 markers would pass a
# stub that such a reader still sees as declaring one, so CR is treated as a
# terminator too and leading whitespace is stripped before the compare.
has_forbidden_marker() {
  local chunk line
  while IFS= read -r chunk || [[ -n "$chunk" ]]; do
    while [[ -n "$chunk" || -n "${chunk+x}" ]]; do
      line="${chunk%%$'\r'*}"
      line="${line#"${line%%[![:space:]]*}"}"
      case "$line" in
      'type: review-findings'* | 'type: fix-pass-record'* | 'branch:'* | '## Findings'*)
        return 0
        ;;
      *) ;;
      esac
      [[ "$chunk" == *$'\r'* ]] || break
      chunk="${chunk#*$'\r'}"
    done
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
  # `--` is load-bearing: a stub home starting with `-` makes every path an
  # option, `rm` refuses the lot, and the rollback this refusal promises would
  # silently leave the marker-bearing stubs on disk.
  rm -f -- ${written[@]+"${written[@]}"}
  # Only the levels THIS RUN created are removed, deepest first, and `rmdir`
  # refuses a non-empty one. Both halves are load-bearing: `rmdir` on the whole
  # chain would delete a pre-existing empty home the caller had prepared, which
  # is state the run did not create; removing only the innermost level would
  # leave the empty parents behind when `mkdir -p` created more than one, so a
  # refused run would not leave the tree as it found it after all. The first
  # level that will not go stops the walk, since every level above it is that
  # level's parent and cannot be empty either.
  for created_dir in ${created_dirs[@]+"${created_dirs[@]}"}; do
    rmdir -- "$created_dir" 2>/dev/null || break
  done
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
