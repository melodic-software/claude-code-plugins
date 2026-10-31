#!/bin/sh
# guardrails-pre-commit-content v2
# guardrails pre-commit check: secrets and machine-specific paths in the lines
# this commit adds.
#
#   pre-commit-content.sh               the staged changes (git runs it as pre-commit)
#   pre-commit-content.sh --worktree    the uncommitted changes against HEAD,
#                                       untracked files included
#
# The write-path-independent layer for what the secret-pattern-detection and
# hardcoded-path-check guards stop on Write and Edit: a shell command, a script
# or another tool can write a file no Claude Code guard sees, and this check
# reads what reaches a commit. It uses the same pattern libraries, installed
# beside this script as entry assets.
#
# Each file is judged the way a Write or Edit of it would be: a new file on its
# whole content, a changed file on the lines the commit adds, read from the
# index (the work tree with --worktree). Every staged path is judged, a
# force-added gitignored one included; --worktree leaves out untracked
# gitignored files. Skipped: symbolic links, submodules and files over 1 MiB.
# A file holding a NUL byte (whatever a `-diff` attribute says) is judged
# whole for secrets only. The two
# guards' path exemptions apply (tests/fixtures for secrets only).
#
# Findings print as "<path>:<line>: <message>" on stderr and exit 1. The
# message says how to fix the content; this hook never suggests skipping it.
# A text tool that fails mid-scan also exits 1, since the scan is incomplete.
#
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail

# The pattern libraries: beside an installed copy (entry assets), or in the
# plugin's lib/ when run from the plugin itself.
secret_lib="$here/secret-patterns.sh"
[[ -f "$secret_lib" ]] || secret_lib="$here/../lib/secret-detection/secret-patterns.sh"
path_lib="$here/hardcoded-path-patterns.sh"
[[ -f "$path_lib" ]] || path_lib="$here/../lib/path-detection/hardcoded-path-patterns.sh"
# shellcheck source=../lib/secret-detection/secret-patterns.sh
. "$secret_lib" || exit 1
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
. "$path_lib" || exit 1

checks_init pre-commit "$@" || exit 0
MAX_BYTES=1048576

# The scan's text tools, here and in check-lib.sh and the pattern libraries,
# run in pipelines and command substitutions whose status nothing reads, so a
# crashed run would leave text unscanned and the commit passing. These wrappers
# record any failure, and the hook then exits 1. Not failures: 141, a reader
# such as head closing the pipe once it has what it needs, and grep's 1, no
# match.
scan_error="$CHECKS_TMP/scan-error"
scan_tool() {
  local tool=$1 rc
  shift
  command "$tool" "$@"
  rc=$?
  case "$tool:$rc" in
  *:0 | *:141 | grep:1) ;;
  *) : >"$scan_error" ;;
  esac
  return "$rc"
}
awk() { scan_tool awk "$@"; }
grep() { scan_tool grep "$@"; }
sed() { scan_tool sed "$@"; }
sort() { scan_tool sort "$@"; }
cut() { scan_tool cut "$@"; }

# Hardcoded-path exemptions, as hardcoded-path-check.sh has them.
path_exempt() {
  case "$1" in
  *.claude/hooks/* | *.lefthook/*) return 0 ;;
  *settings.local.json | *CLAUDE.local.md) return 0 ;;
  */.venv/* | .venv/* | */node_modules/* | node_modules/*) return 0 ;;
  *.env.example | *.env.sample | *.env.template) return 0 ;;
  *.claude/skills/*/context/* | *.claude/skills/*/completed/*) return 0 ;;
  */lib/secret-detection/* | */lib/path-detection/*) return 0 ;;
  # The same libraries as this entry's shared-scope assets.
  .githooks/guardrails/secret-patterns.sh | .githooks/guardrails/hardcoded-path-patterns.sh | \
    .githooks/guardrails/machine-path-patterns.sh) return 0 ;;
  *) return 1 ;;
  esac
}

# Secret exemptions, as secret-pattern-detection.sh has them: the path set
# plus test fixtures.
secret_exempt() {
  case "$1" in
  *tests/fixtures/* | *tests/testdata/* | *Tests/fixtures/* | *Tests/testdata/*) return 0 ;;
  *) path_exempt "$1" ;;
  esac
}

# The repository path itself is a finding, unless the checkout sits at, above
# or below the home directory, where every home path would match it.
scan_root="$PWD"
home="${HOME:-${USERPROFILE:-}}"
home="${home%/}"
if [[ -n "$home" ]]; then
  case "$PWD/" in
  "$home/" | "$home"/*) scan_root="" ;;
  *) ;;
  esac
  case "$home/" in
  "$PWD"/*) scan_root="" ;;
  *) ;;
  esac
fi

# src_has_nul <file>: checks_has_nul's test, on content already read out.
src_has_nul() {
  local LC_ALL=C chunk
  IFS= read -r -d '' -n 8000 chunk <"$1" && ((${#chunk} < 8000))
}

# ascii_text <text>: 0 when every byte is ASCII. A case pattern, as in
# hpp::prefilter, since Git Bash's regex decodes UTF-8 even under C.
ascii_text() {
  local LC_ALL=C non_ascii=$'[!\x01-\x7f]'
  [[ $1 != *$non_ascii* ]]
}

checks_changed_lines

# added_only <path>: the file with every line the commit does not add blanked,
# so line numbers hold and only added text is scanned.
added_only() {
  awk -v want="$1" -v ranges="$CHECKS_TMP/ranges" '
    BEGIN { while ((getline l < ranges) > 0) { split(l, r, "\t"); if (r[1] == want) { n++; s[n] = r[2] + 0; e[n] = r[3] + 0 } } }
    { keep = 0; for (i = 1; i <= n; i++) if (NR >= s[i] && NR <= e[i]) { keep = 1; break } print (keep ? $0 : "") }'
}

# scan_failed <path>: a file this check could not read out or write down
# blocks the commit, since the scan would otherwise skip it.
scan_failed() {
  printf 'guardrails: %s: could not be scanned (is %s full?); free space there, then commit again.\n' "$1" "$CHECKS_TMP" >&2
  exit 1
}

# Each finding is written behind "<file index><TAB><0 secret, 1 path><TAB>",
# and untag puts a sink back in file order, secrets first, as the final sort -u
# keeps the first of findings that share a path and line.
tab=$'\t'
untag() {
  sort -s -t "$tab" -k1,1n -k2,2n "$1" | cut -f3-
}

# secret_findings <path> <file index>: secrets::scan_text output on stdin, as
# findings.
secret_findings() {
  sed -n 's/^\(.*\) (line \([0-9,]*\))$/\2 \1/p' |
    while read -r nums label; do
      for n in ${nums//,/ }; do
        printf '%s\t0\t%s:%s: secret or credential pattern: %s\n' "$2" "$1" "$n" "$label"
      done
    done
}

# hpp_judge <i>: hpp::scan_text on one file, its findings to the file's sink.
hpp_judge() {
  hpp::scan_text "${texts[$1]}" "$scan_root" "$PWD/${names[$1]}" |
    awk -v f="${names[$1]}" -v tag="${order[$1]}" '
      /^[^ \t].*:$/ && !/^[0-9]+:/ { label = substr($0, 1, length($0) - 1); next }
      match($0, /^[0-9]+:/) { printf "%s\t1\t%s:%s: machine-specific path (%s)\n", tag, f, substr($0, 1, RLENGTH - 1), label }' >>"${sinks[$1]}"
}

# hpp_sweep <from> <to>: judge the files pool[from..to). Their texts joined
# scan clean only when each one does: every check is per line, and a joined
# scan names no file, so no OS context turns a check off. A group that does
# not scan clean is halved down to single files, each judged on its own. The
# pool holds ASCII text only, so no grep reads an encoding error in one file
# as binary and stays quiet about a match in another. A group over
# JOIN_MAX bytes is split unprobed: the scan hands awk its matched line
# numbers in one argument, and a joined text past that size could outgrow the
# argument limit (32 KiB on Windows), fail the awk and scan clean.
JOIN_MAX=32768
hpp_sweep() {
  local from=$1 to=$2 i t joined="" mid
  if ((to - from == 1)); then
    hpp_judge "${pool[from]}"
    return
  fi
  for ((i = from; i < to && ${#joined} <= JOIN_MAX; i++)); do
    t="${texts[pool[i]]}"
    joined+="$t"
    [[ "${t: -1}" == $'\n' ]] || joined+=$'\n'
  done
  if ((${#joined} <= JOIN_MAX)); then
    hpp::scan_text "$joined" "$scan_root" >/dev/null && return
  fi
  mid=$(((from + to) / 2))
  hpp_sweep "$from" "$mid"
  hpp_sweep "$mid" "$to"
}

# The files to judge: paths[i] names one and, in pre-commit, keeps[i] is its
# staged object id. Pre-commit takes the staged modes and object ids from one
# raw diff, which lists the files checks_files does, and the sizes from one
# batch query, so each file costs one git process, the one that reads it out.
paths=()
keeps=()
mkdir "$CHECKS_TMP/scan" || scan_failed .
if [[ "$CHECKS_MODE" == worktree ]]; then
  while IFS= read -r -d '' f; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    (($(wc -c <"$f" | tr -d ' ') <= MAX_BYTES)) || continue
    paths+=("$f")
  done < <(checks_files)
else
  staged=()
  blobs=()
  # ":<mode> <mode> <id> <id> <status>", then the path; a rename or copy
  # names its source first.
  while IFS= read -r -d '' meta && IFS= read -r -d '' f; do
    case "${meta##* }" in
    R* | C*) IFS= read -r -d '' f || break ;;
    *) ;;
    esac
    rest="${meta#* }"
    case "${rest%% *}" in
    100644 | 100755) ;;
    *) continue ;;
    esac
    rest="${rest#* }"
    rest="${rest#* }"
    staged+=("$f")
    blobs+=("${rest%% *}")
  done < <(checks_diff --raw --no-abbrev -z --diff-filter=ACMR)
  sizes=()
  if ((${#blobs[@]})); then
    while read -r s; do
      sizes+=("$s")
    done < <(printf '%s\n' "${blobs[@]}" | git cat-file --batch-check='%(objectsize)' 2>/dev/null)
  fi
  for ((i = 0; i < ${#staged[@]}; i++)); do
    s="${sizes[i]:-0}"
    [[ "$s" =~ ^[0-9]+$ ]] || s=0
    ((s <= MAX_BYTES)) || continue
    paths+=("${staged[i]}")
    keeps+=("${blobs[i]}")
  done
fi

# names[i], texts[i], sinks[i] and order[i]: each file the scans read, its
# text, where its findings go and its index in paths; $CHECKS_TMP/scan/<i>
# holds the same text for a grep that reads every file in one process.
out="$CHECKS_TMP/findings"
whole="$CHECKS_TMP/findings-whole"
: >"$out"
: >"$whole"
names=()
texts=()
sinks=()
order=()
scanned=0
for ((i = 0; i < ${#paths[@]}; i++)); do
  f="${paths[i]}"
  src="$f"
  if [[ "$CHECKS_MODE" != worktree ]]; then
    src="$CHECKS_TMP/blob"
    git cat-file blob "${keeps[i]}" >"$src" 2>/dev/null || scan_failed "$f"
  fi
  if src_has_nul "$src"; then
    # A NUL byte must not hide a secret: scan the whole raw content for the
    # secret patterns twice, each NUL read as a space, then each NUL deleted
    # (UTF-16LE text puts one after every ASCII byte). Both keep newlines, so
    # line numbers hold; the second pass reports only labels the first missed.
    # Path patterns are not judged here, so an ordinary binary still commits.
    secret_exempt "$f" && continue
    text="$(tr '\0' ' ' <"$src"; printf x)"
    packed="$(tr -d '\0' <"$src"; printf x)"
    {
      secrets::scan_text "${text%x}"
      echo --
      secrets::scan_text "${packed%x}"
    } | awk '$0 == "--" { p2 = 1; next }
      { l = $0; sub(/ \(line [0-9,]*\)$/, "", l) }
      p2 && (l in seen) { next }
      !p2 { seen[l] } { print }' | secret_findings "$f" "$i" >>"$whole"
    continue
  fi
  sink="$out"
  if [[ "$f" == *[\"\\[:cntrl:]]* ]]; then
    # Git quotes such a name whatever core.quotePath says, so the range table
    # holds no entry for it: the file is judged whole, past the range filter.
    text="$(cat -- "$src"; printf x)"
    sink="$whole"
  else
    text="$(added_only "$f" <"$src"; printf x)"
  fi
  text="${text%x}"
  # A match, not ${text//[[:space:]]/}, whose run time grows with the square
  # of the text's size (over 30 s for one 200 KB file).
  [[ "$text" == *[![:space:]]* ]] || continue
  names[scanned]="$f"
  texts[scanned]="$text"
  sinks[scanned]="$sink"
  order[scanned]="$i"
  printf '%s' "$text" >"$CHECKS_TMP/scan/$scanned" || scan_failed "$f"
  scanned=$((scanned + 1))
done

# One grep lists the files a secret pattern matches, the test
# secrets::any_match makes on each, and only those are scanned. When the grep
# fails, every file is, so this grep bypasses the scan_tool wrapper.
secret_args=()
for p in "${SECRET_PATTERNS[@]}"; do
  secret_args+=(-e "$p")
done
hits=()
if ((scanned)); then
  : >"$CHECKS_TMP/secret-hits" || scan_failed .
  LC_ALL=C command grep -rlE "${secret_args[@]}" -- "$CHECKS_TMP/scan" >"$CHECKS_TMP/secret-hits" 2>/dev/null
  if (($? > 1)); then
    for ((i = 0; i < scanned; i++)); do
      hits[i]=1
    done
  else
    while IFS= read -r p; do
      p="${p##*/}"
      [[ "$p" =~ ^[0-9]+$ ]] && hits[p]=1
    done <"$CHECKS_TMP/secret-hits"
  fi
fi
for ((i = 0; i < scanned; i++)); do
  [[ -n "${hits[i]:-}" ]] || continue
  secret_exempt "${names[i]}" && continue
  secrets::scan_text "${texts[i]}" | secret_findings "${names[i]}" "${order[i]}" >>"${sinks[i]}"
done

# hpp::prefilter clears most files with no process. Of the rest, ASCII text
# goes to hpp_sweep and other text is judged file by file.
pool=()
for ((i = 0; i < scanned; i++)); do
  path_exempt "${names[i]}" && continue
  hpp::prefilter "${texts[i]}" "$scan_root"
  [[ $HPP_GATE == clean ]] && continue
  if ascii_text "${texts[i]}"; then
    pool+=("$i")
  else
    hpp_judge "$i"
  fi
done
((${#pool[@]} == 0)) || hpp_sweep 0 "${#pool[@]}"

{
  untag "$out" | checks_filter_findings
  untag "$whole"
} | sort -u -t: -k1,1 -k2,2n >"$CHECKS_TMP/blocking"
if [[ -e "$scan_error" ]]; then
  cat "$CHECKS_TMP/blocking" >&2
  printf 'guardrails: the content scan failed (see the error above), so this change was not fully scanned; fix that error, then commit again.\n' >&2
  exit 1
fi
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'guardrails: remove the secrets or machine-specific paths above from the change (use a placeholder, an environment variable or a portable path), then commit again.\n' >&2
exit 1
