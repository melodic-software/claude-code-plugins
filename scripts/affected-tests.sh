#!/usr/bin/env bash
# Select the test suites that cover a set of changed files, so a change runs the
# suites it affects instead of the whole corpus. Four ecosystems carry suites
# here and each names them differently: shell **/*.test.sh, Node **/*.test.js
# and **/*.test.mjs, Python **/test_*.py, and Pester **/*.Tests.ps1.
#
# The full corpus is tens of minutes of wall clock on a Windows box
# (Git Bash pays ~140ms per process spawn, and these suites are spawn-bound),
# which is long enough that nobody runs it locally and regressions reach CI.
#
#   scripts/affected-tests.sh                    list the suites covering the diff vs the base ref
#   scripts/affected-tests.sh --run              ... and run them, sequentially
#   scripts/affected-tests.sh --run --jobs N     ... N shell suites at a time
#   scripts/affected-tests.sh path/a.sh path/b   ... for explicit paths instead of a diff
#   scripts/affected-tests.sh --base <ref>       use <ref> as the diff base (default: origin/main)
#   scripts/affected-tests.sh --explain          report WHY each suite was selected (stderr)
#   scripts/affected-tests.sh --allow-unmapped   downgrade an unmapped file to a warning
#   scripts/affected-tests.sh --unmapped-corpus  select an unmapped file's whole language corpus (exit 4)
#   scripts/affected-tests.sh --shard <i>/<n>    keep only leg i of n of the selection
#   scripts/affected-tests.sh --print-fanout P   print the copy set DERIVED for shared source P
#   scripts/affected-tests.sh --replay <range> [--against <ref>]
#                                                select every first-parent commit of <range> against
#                                                its parent; with --against, diff each selection with
#                                                the selector at <ref> (see REPLAY)
#
# --with-always is accepted and changes nothing: the suites that assert against
# the live tree declare what they read in scripts/affected-tests-scopes.txt (R8).
#
# Exit: 0 selected (or nothing to do); 1 an unmapped changed file, or a failing
# suite under --run; 2 usage or a broken derivation; 3 --run ran every shell
# suite it selected but ALSO selected suites in other ecosystems, whose runner
# it deliberately will not guess (see the --run note at the foot of this file);
# 4 --unmapped-corpus widened the selection to the corpus of an unmapped file's
# language. Under --run the first that applies wins, in the order 1, 3, 4.
#
# HOST: --run IS A LINUX GATE. On a Windows Git Bash host a standing set of
# suites fails for reasons that belong to the host and not to the tree: text-mode
# CRLF translation (a native jq and Git Bash line-ending handling), no
# unprivileged symlink right, MSYS drive-letter paths against the POSIX form in
# fixture assertions, and a missing `scc`. Its exit code there reports host
# capability, so it cannot say whether a change is good, and the repo does not
# support it as a local gate on Windows. Selection itself is host-neutral: use
# the listing forms to see what a change affects and run individual suites by
# hand. CI's Linux lanes are the gate that decides.
#
# SHARDING. `--shard <i>/<n>` narrows the SELECTION, not the derivation: every
# rule below runs in full, the unmapped check fires in full, and only then is
# the sorted suite list partitioned by index modulo n. The union of legs
# 0..n-1 is exactly the unsharded selection and no two legs share a suite.
# Modulo rather than contiguous blocks, because the sorted list clusters suites
# by directory. An EMPTY leg exits 0: "this leg had nothing to run" and
# "nothing was affected" are the same statement about that runner.
#
# FAIL LOUD, NOT OPEN. A changed file that maps to NO suite is an ERROR, not an
# empty selection: "zero suites" reads as "nothing to run" when it actually
# means "nothing here knows what covers this". The exceptions are the path
# classes recorded in scripts/affected-tests-no-suite.txt, each of which names
# the lane that does cover it, and deletions, which have no content left to
# cover. --allow-unmapped downgrades the error to a warning; --unmapped-corpus
# keeps the report and adds every suite of the file's language to the selection:
# the shell corpus for .sh and .bash, Python for .py, Node for .js .mjs .cjs,
# Pester for .ps1 .psm1, and the shell corpus for any other file, because shell
# suites are the ones that read data files out of the tree.
#
# SELECTION RULES. A suite runs when the changed file is code the suite runs or
# loads, or data the suite (or code it runs) reads. Every rule finds that
# relation from text and paths, so each one is written to say no when the text
# does not show the relation.
#   R1 self          a changed suite selects itself, in any ecosystem.
#   R2 co-located    <dir>/<stem>.<ext> selects the sibling suites covering it,
#                    under each ecosystem's own naming: <stem>.test.sh,
#                    <stem>.test.js, <stem>.test.mjs, <stem>.Tests.ps1,
#                    <dir>/test_<stem>.py and <dir>/tests/test_<stem>.py, the
#                    two Python forms also with `-` folded to `_`. Every match is
#                    taken: a .py can carry a test_<stem>.py and a wrapping
#                    <stem>.test.sh at once.
#   R3 same language a file in the changed file's language that NAMES it (see
#                    MATCHING) on a line that is not only a comment is a
#                    dependent; R1, R2 and R3 then apply to it, transitively,
#                    with no depth cap. A suite that names it is selected. This is
#                    what carries a library change out to what sources it.
#   R4 other language a file in another language counts only where the naming
#                    line runs or loads the file: an interpreter or process API on
#                    the line (bash, sh, python3, node, pwsh, source, subprocess,
#                    spawn*, exec*, ...), or a path to the file rather than its
#                    bare name. Nothing else on the line counts: not the named
#                    file being a shell script, not the naming file sitting in
#                    the same directory. A chain takes at most one such
#                    transition and then keeps walking its new language.
#                    A data file (any extension that is not code) reaches code of
#                    every language that names it, and that first step spends no
#                    transition: data has no language of its own to stay inside.
#   R5 shared lib    a file that is the `src` of a scripts/sync-*.sh selects
#                    every path in that script's published `copy` list, then R2,
#                    R3 and R4 on each copy. The copy set is DERIVED from
#                    `--print-manifest` on every run, never hardcoded or scraped,
#                    because the manifests are what CI's sync lanes enforce.
#   R6 sync script   a changed scripts/sync-*.sh selects its own co-located test
#                    plus everything its published `src` selects.
#   R7 path class    a path under plugins/autonomy/reference/ selects the
#                    plugin-contract validator's suite, which bans vendor names
#                    across that directory without naming any file in it.
#   R8 declared scope a suite that enumerates a directory of the live tree
#                    (a grep -r, a find, a glob over a plugin or scripts/), or
#                    builds a path from parts, never names the files it reads,
#                    so scripts/affected-tests-scopes.txt declares them, one
#                    `<suite> <glob>...` line per suite:
#                        plugins/github/github.test.sh  plugins/github/*
#                    A changed file matching a glob selects the suite and counts
#                    as mapped. The globs use the dialect of the no-suite list:
#                    matched against the repo-relative path, `*` crosses `/`.
#                    An entry naming no suite fails every run (exit 2), and a
#                    glob matching no file fails the run that changes the list.
#
# MATCHING. One file NAMES another when the basename stands in a line as a WHOLE
# PATH TOKEN: bounded on both sides by a character outside [A-Za-z0-9_.-]. `/`
# is outside that class, so a path-qualified mention names the file. A trailing
# run of `.` is sentence punctuation and is dropped, and so is a leading run of
# `-`, `+`, `=`, `?` or `.`, so `${TARGET:-<name>}` and `...<name>` name <name>.
# A basename buried inside a longer token (`handoff-paths.json` against
# `paths.js`) is not a mention: a substring match there is FALSE COVERAGE, a
# file nothing covers coming back mapped at exit 0. A basename the token rule
# cannot spell, one with a character outside the class, keeps the substring
# test rather than losing its coverage.
#
# MANIFESTS. plugin.json, marketplace.json, hooks.json, settings.json,
# package.json, package-lock.json, CHANGELOG.md and LICENSE select no suite
# through a mention: a suite that reads one reads its name or version, and the
# manifest, changelog and catalog gates own those files. Only R1, R2 and a
# declared scope (R8) reach a suite from them; anything else is on the no-suite
# list.
#
# AMBIGUOUS NAMES. A basename two or more files carry, and the structural docs
# (README.md, SKILL.md, AGENTS.md, CLAUDE.md, index.md), name a specific file
# only when the mention RESOLVES to it, because a bare `SKILL.md` or
# `config.json` says nothing about which one. Any mention from the file's own
# directory resolves. A bare name resolves from a directory above the file when
# no other file of that name sits below that directory
# (`FIXTURES / "questions.json"`), and never otherwise. A path resolves when it
# ends in the shortest suffix of the file's path, two components or more, that
# no other file of that name ends in, or in the file's path relative to a
# directory below the repository root that holds both files, when that relative
# path has a directory in it: `$SCRIPT_DIR/lib/x.sh` from a script beside lib/,
# `$PLUGIN_DIR/skills/interview/SKILL.md` from inside the plugin. A path that
# spells only the name (`$SKILL_DIR/SKILL.md`, `$T/README.md`) or that is
# relative to the root alone (`$ROOT/.github/workflows/ci.yml`) does not
# resolve: tests build the same path under a temporary directory as often as
# they read the real file, so a suite that reads such a file declares it (R8),
# as the strace of every suite showed where one does. A shared
# library's source and copies are the exception and keep the plain rule: R5's
# copies share a basename on purpose, change together with their source, and a
# suite naming its own plugin's copy is naming the shared source.
#
# COMMENTS. A line that is only a comment (`#` in shell, Python and
# PowerShell; `//`, `/*` or a `*` continuation in Node) names nothing, in suites
# and in code alike: prose that cites a file is not a dependency on it. A
# `# shellcheck source=` directive and a JSDoc type import (`@import`,
# `import('...')`) are read by tools and still count, as does a trailing
# comment on a code line.
#
# PYTHON IMPORTS. An import never spells the .py, so R3 also reads Python
# import lines: `import foo`, `from foo import x`, `from . import foo` and the
# dotted forms name foo.py (or the package foo/__init__.py) when the importer
# sits in the directory foo is imported from or below it, when the dotted path
# spells the path of foo, or when foo is the only module of that name in the
# importer's plugin, the reach of a sys.path insert.
#
# REPLAY. `--replay <range>` selects every first-parent commit of <range>
# (`git rev-list --first-parent <range>`) against its parent, the squash-merged
# pull request's net diff, in a scratch clone checked out at that commit, with
# THIS script's rules, no-suite list and scopes list, so it answers "what would
# this selector have run for those pull requests". It prints one
# `commit <sha> <suites> <unmapped>` line per commit, an indented
# `unmapped <path>` line per unmapped file and one indented
# `<suite>  (<reason>)` line per suite. With `--against <ref>` it also runs the
# selector at <ref>, with <ref>'s own lists, on the same tree, and prints only
# the suites that differ (`+` this script only, `-` <ref> only, each with its
# reason) after a `commit <sha> <new> <old> <new-unmapped> <old-unmapped>` line
# and its `unmapped` lines, so a selector change shows its blast radius. Both
# sides run with --allow-unmapped; a summary on stderr counts suites per commit
# (p50, p95, max, total) and the commits with an unmapped file on each side.
# Each run is pointed at the scratch clone with AFFECTED_TESTS_ROOT, and at the
# lists with AFFECTED_TESTS_NO_SUITE and AFFECTED_TESTS_SCOPES.
#
# MECHANICALLY the reverse lookup is two stages. `git grep -F` finds the
# candidate LINES with the substring test, which keeps git's fixed-string fast
# path (an ERE alternation of bounded basenames took minutes per level); one
# awk pass then drops comment lines, splits each line into tokens, and keeps the
# (file, name) pairs MATCHING and AMBIGUOUS NAMES let stand, marking each with
# whether its line runs or loads the file.
# Both stages fail loud; see the call site in select_for.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SELF="$SCRIPT_DIR/${BASH_SOURCE[0]##*/}"
cd "${AFFECTED_TESTS_ROOT:-$SCRIPT_DIR/..}" || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

NO_SUITE_LIST="${AFFECTED_TESTS_NO_SUITE:-scripts/affected-tests-no-suite.txt}"
SCOPES_LIST="${AFFECTED_TESTS_SCOPES:-scripts/affected-tests-scopes.txt}"

# Basenames that name a repository-wide role, reached only through a resolved
# mention (AMBIGUOUS NAMES in the header), however few files carry them today.
STRUCTURAL_BASENAMES=" README.md SKILL.md AGENTS.md CLAUDE.md index.md "
# Manifests and changelogs, which no mention reaches (MANIFESTS in the header).
MANIFEST_BASENAMES=" plugin.json marketplace.json hooks.json settings.json package.json package-lock.json "
MANIFEST_BASENAMES+="CHANGELOG.md LICENSE "

# Print the header block (everything after the shebang up to the first
# non-comment line) with its comment markers stripped.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
    "${BASH_SOURCE[0]}"
}

base_ref=""
do_run=0
allow_unmapped=0
unmapped_corpus=0
explain=0
print_fanout=""
shard_spec=""
replay_range=""
against_ref=""
jobs=1
# Whether --shard was SUPPLIED, tracked apart from its value: `--shard=` with an
# empty right-hand side is what an unset environment variable produces, and it
# must not read as "no shard requested" and run everything on every leg.
shard_given=0
shard_index=0
shard_total=1
declare -a explicit_paths=()

# parse_shard <spec>: accept exactly `<i>/<n>` with i and n decimal, n >= 1 and
# 0 <= i < n. A spec this function cannot read must never become leg 0 of 1,
# which RUNS EVERYTHING and would report a full pass from a typo'd fan-out.
parse_shard() {
  local spec="$1" i n
  [[ "$spec" =~ ^[0-9]+/[0-9]+$ ]] || return 1
  i="${spec%%/*}"
  n="${spec##*/}"
  # Strip leading zeros so `08` is 8 rather than an octal parse error.
  i=$((10#$i))
  n=$((10#$n))
  ((n >= 1)) || return 1
  ((i < n)) || return 1
  shard_index="$i"
  shard_total="$n"
  return 0
}

# need_value <flag> <argc> <value>: usage errors exit 2, never 1, which is
# spoken for by an unmapped file and a failing suite.
need_value() {
  if [[ "$2" -lt 2 || -z "$3" ]]; then
    echo "error: $1 needs a value ($4)." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --run) do_run=1 ;;
  --allow-unmapped) allow_unmapped=1 ;;
  --unmapped-corpus) unmapped_corpus=1 ;;
  --explain) explain=1 ;;
  --with-always) ;;
  --jobs)
    need_value "$1" $# "${2:-}" "a positive integer"
    jobs="$2"
    shift
    ;;
  --jobs=*) jobs="${1#--jobs=}" ;;
  --base)
    need_value "$1" $# "${2:-}" "a ref"
    base_ref="$2"
    shift
    ;;
  --base=*) base_ref="${1#--base=}" ;;
  --shard)
    need_value "$1" $# "${2:-}" "<index>/<total>"
    shard_spec="$2"
    shard_given=1
    shift
    ;;
  --shard=*)
    shard_spec="${1#--shard=}"
    shard_given=1
    ;;
  --print-fanout)
    need_value "$1" $# "${2:-}" "a path"
    print_fanout="$2"
    shift
    ;;
  --replay)
    need_value "$1" $# "${2:-}" "a revision range"
    replay_range="$2"
    shift
    ;;
  --against)
    need_value "$1" $# "${2:-}" "a ref"
    against_ref="$2"
    shift
    ;;
  --)
    shift
    explicit_paths+=("$@")
    break
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  *) explicit_paths+=("$1") ;;
  esac
  shift
done

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --jobs wants a positive integer; got: $jobs" >&2
  exit 2
fi
if [[ "$shard_given" -eq 1 ]] && ! parse_shard "$shard_spec"; then
  echo "error: --shard wants <index>/<total> with total >= 1 and 0 <= index < total; got: $shard_spec" >&2
  exit 2
fi
if [[ "$allow_unmapped" -eq 1 && "$unmapped_corpus" -eq 1 ]]; then
  echo "error: --allow-unmapped and --unmapped-corpus answer the same question two ways; pass one." >&2
  exit 2
fi
if [[ -n "$against_ref" && -z "$replay_range" ]]; then
  echo "error: --against only applies to --replay." >&2
  exit 2
fi
if [[ -n "$replay_range" ]] && [[ ${#explicit_paths[@]} -gt 0 || -n "$base_ref" || "$do_run" -eq 1 || "$shard_given" -eq 1 ]]; then
  echo "error: --replay takes its changed files from each commit; it combines with no paths, --base, --run or --shard." >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/affected-tests.XXXXXX")" || exit 2
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# Sync-manifest derivation (R5/R6)
# ---------------------------------------------------------------------------

# Published --print-manifest format (scripts/lib/sync-cluster.sh,
# scripts/sync-shared-copies.sh), one block per canonical source:
#   src<TAB><path>     opens a block; empty path means the key was declared blank
#   copy<TAB><path>    zero or more per block; path may still be a glob
# A script that does not implement the flag (usage on stderr, empty stdout) or
# that prints neither key is a helper sharing the sync-*.sh prefix and is
# skipped. A block with copy lines (or an empty src key) but no non-empty src
# is a half-manifest and is fatal.

# SYNC_SRC_COPIES maps a sync source path to its newline-separated copy paths.
# SYNC_SCRIPT_SRC maps a sync script to its newline-separated source paths.
declare -A SYNC_SRC_COPIES=()
declare -A SYNC_SCRIPT_SRC=()

# register_sync_block <script> <src> <has-copy-key> [<copy pattern>...]
register_sync_block() {
  local script="$1" src="$2" has_copy_key="$3" pattern match
  shift 3
  local -a expanded=()
  if [[ -z "$src" ]]; then
    echo "error: $script --print-manifest declared copies but no src= — the shared-lib derivation cannot read it." >&2
    echo "       Teach scripts/affected-tests.sh the new manifest shape; do not hardcode a copy list." >&2
    exit 2
  fi
  SYNC_SCRIPT_SRC["$script"]+="$src"$'\n'
  # A src with NO copy key at all is a canonical-only cluster: the lib has
  # landed and no plugin carries it yet. It registers with an empty copy set.
  if ((has_copy_key == 0)); then
    SYNC_SRC_COPIES["$src"]=""
    return 0
  fi
  for pattern in "$@"; do
    if [[ -e "$pattern" ]]; then
      expanded+=("$pattern")
      continue
    fi
    # shellcheck disable=SC2086 # a manifest entry may still be a glob;
    # splitting is the expansion, and no path in this repo contains whitespace.
    for match in $pattern; do
      [[ -e "$match" ]] && expanded+=("$match")
    done
  done
  if [[ ${#expanded[@]} -eq 0 ]]; then
    echo "error: $script yielded ZERO copy paths for $src." >&2
    echo "       An empty derivation is the hardcoded-list failure mode one level up: it would" >&2
    echo "       silently stop fanning a shared-lib change out to its carrying plugins." >&2
    exit 2
  fi
  printf -v SYNC_SRC_COPIES["$src"] '%s\n' "${expanded[@]}"
}

build_sync_map() {
  local script line kind value rc errfile outfile i
  local -a block_src=() block_has_copy=() block_patterns=() patterns=()
  outfile="$WORK_DIR/print-manifest.out"
  errfile="$WORK_DIR/print-manifest.err"
  for script in scripts/sync-*.sh; do
    [[ -f "$script" ]] || continue
    case "$script" in
    *.test.sh) continue ;;
    *) ;;
    esac
    rc=0
    bash "$script" --print-manifest >"$outfile" 2>"$errfile" || rc=$?

    # Each src line opens a block; a copy line before any src opens one with an
    # empty src, which register_sync_block rejects as half a manifest.
    block_src=()
    block_has_copy=()
    block_patterns=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      kind="${line%%$'\t'*}"
      if [[ "$kind" == "$line" ]]; then
        value=""
      else
        value="${line#*$'\t'}"
      fi
      case "$kind" in
      src)
        block_src+=("$value")
        block_has_copy+=(0)
        block_patterns+=("")
        ;;
      copy)
        if [[ ${#block_src[@]} -eq 0 ]]; then
          block_src+=("")
          block_has_copy+=(0)
          block_patterns+=("")
        fi
        i=$((${#block_src[@]} - 1))
        block_has_copy[i]=1
        block_patterns[i]+="$value"$'\n'
        ;;
      *) ;;
      esac
    done <"$outfile"

    if ((rc != 0)); then
      # usage / unknown-flag: a helper that does not implement the surface.
      if [[ ! -s "$outfile" ]] && grep -q '^usage:' "$errfile"; then
        continue
      fi
      echo "error: $script --print-manifest failed (exit $rc)." >&2
      cat "$errfile" >&2
      exit 2
    fi

    # A script matching scripts/sync-*.sh that publishes NEITHER key is a
    # helper that happens to share the prefix, and opens no block. Exiting on
    # it would turn a required lane red for every pull request the day such a
    # helper lands. Half a manifest is still fatal.
    for i in "${!block_src[@]}"; do
      patterns=()
      while IFS= read -r line; do
        [[ -z "$line" ]] || patterns+=("$line")
      done <<<"${block_patterns[i]}"
      register_sync_block "$script" "${block_src[i]}" "${block_has_copy[i]}" ${patterns[@]+"${patterns[@]}"}
    done
  done
  if [[ ${#SYNC_SCRIPT_SRC[@]} -eq 0 ]]; then
    echo "error: no scripts/sync-*.sh manifests found — shared-lib fan-out would be silently empty." >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Tree index: every file, the ambiguous basenames, the declared scopes
# ---------------------------------------------------------------------------

declare -A AMBIGUOUS=()   # basename -> 1 when two or more files carry it
declare -A SYNC_MEMBER=() # path -> 1 for a shared library's source and each copy
declare -a SCOPE_SUITES=() SCOPE_GLOBS=()
# build_tree_index: every tracked or untracked-unignored file, listed once for
# the ambiguous-name set, the reverse lookup's resolution, the declared scopes
# and the unmapped corpora. Fatal on a failed listing: a short list under-selects.
build_tree_index() {
  local b src copy suite
  if ! git ls-files --cached --others --exclude-standard >"$WORK_DIR/all-files" ||
    ! awk '{ sub(/.*\//, ""); if (++count[$0] == 2) print }' "$WORK_DIR/all-files" >"$WORK_DIR/ambiguous"; then
    echo "error: listing the tree failed." >&2
    exit 2
  fi
  while IFS= read -r b; do
    AMBIGUOUS["$b"]=1
  done <"$WORK_DIR/ambiguous"
  for src in "${!SYNC_SRC_COPIES[@]}"; do
    SYNC_MEMBER["$src"]=1
    while IFS= read -r copy; do
      [[ -n "$copy" ]] && SYNC_MEMBER["$copy"]=1
    done <<<"${SYNC_SRC_COPIES[$src]}"
  done

  # Every Python import line, read once for PYTHON IMPORTS. Fatal on a git
  # error for the same reason as the reverse lookup: no lines reads as no edges.
  local rc=0
  git grep --untracked -I -E '^[[:space:]]*(from[[:space:]]+[.A-Za-z_][.A-Za-z0-9_]*[[:space:]]+import|import[[:space:]]+[A-Za-z_])' \
    -- '*.py' >"$WORK_DIR/py-imports" || rc=$?
  if [[ "$rc" -gt 1 ]]; then
    echo "error: 'git grep' failed (exit $rc) listing the Python import lines." >&2
    exit 2
  fi

  # R8, one `<suite> <glob>...` line per suite. An entry naming no suite fails
  # the run: a declaration must not outlive what it declares. A replay hands in
  # the list of the tree it started from, whose suites an older commit may lack.
  local -a entries=() words=()
  local entry i
  if [[ ! -f "$SCOPES_LIST" ]]; then
    echo "error: missing $SCOPES_LIST, the declared test scopes (R8)." >&2
    exit 2
  fi
  read_list::into entries "$SCOPES_LIST" --comments inline || exit 2
  for entry in ${entries[@]+"${entries[@]}"}; do
    read -r -a words <<<"$entry"
    suite="${words[0]}"
    if [[ -z "${AFFECTED_TESTS_SCOPES:-}" ]] && { ! is_suite_path "$suite" || [[ ! -f "$suite" ]]; }; then
      echo "error: $SCOPES_LIST names '$suite', which is not a suite; update or remove the entry." >&2
      exit 2
    fi
    for ((i = 1; i < ${#words[@]}; i++)); do
      SCOPE_SUITES+=("$suite")
      SCOPE_GLOBS+=("${words[i]}")
    done
  done
}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

declare -A SUITES=()   # suite path -> reason
declare -a UNMAPPED=() # changed paths that mapped to nothing
declare -a DELETED=()  # changed paths that mapped to nothing AND no longer exist

# SEED_HITS counts the suites the CURRENT seed reached, whether or not an
# earlier seed had already selected them: counting only new ones reported the
# second of two files sharing a suite as unmapped.
SEED_HITS=0
add_suite() {
  local suite="$1" reason="$2"
  [[ -f "$suite" ]] || return 1
  if [[ -z "${SUITES[$suite]:-}" ]]; then
    SUITES["$suite"]="$reason"
  fi
  SEED_HITS=$((SEED_HITS + 1))
  return 0
}

# is_suite_path <path> -> 0 when the path IS a test suite, in any ecosystem
# this repo carries. Python PREFIXES test_<stem>.py, so its arm tests the
# basename rather than the whole path.
is_suite_path() {
  case "$1" in
  *.test.sh | *.test.js | *.test.mjs | *.Tests.ps1) return 0 ;;
  *) ;;
  esac
  case "${1##*/}" in
  test_*.py) return 0 ;;
  *) ;;
  esac
  return 1
}

# lang_family <path> -> sets LANG_FAMILY to the ecosystem the path belongs to.
# A global rather than stdout: a command substitution forks, and this runs once
# per frontier path and per lookup hit. Anything unrecognized gets its own
# `ext:` bucket rather than a shared "other", and an `ext:` origin is data (R4).
LANG_FAMILY=""
lang_family() {
  case "$1" in
  *.sh | *.bash) LANG_FAMILY='sh' ;;
  *.js | *.mjs | *.cjs) LANG_FAMILY='node' ;;
  *.py) LANG_FAMILY='py' ;;
  *.ps1 | *.psm1) LANG_FAMILY='ps' ;;
  *) LANG_FAMILY="ext:${1##*.}" ;;
  esac
}

# token_hits <plain> <resolve> <matched-lines> <hits>
# Reduce `git grep`'s SUBSTRING hits to the mentions the rules mean. Inputs:
# the frontier paths this level looks up by plain basename, those whose names
# must RESOLVE (AMBIGUOUS NAMES), and the `<path>:<line>` grep output. Output,
# one line per pair:
#   p<TAB><path><TAB><basename><TAB><1 when a kept line runs or loads it, else 0>
#   r<TAB><path><TAB><resolved frontier path>
token_hits() {
  awk -v plainf="$1" -v resf="$2" -v allf="$WORK_DIR/all-files" '
    function dir_of(p) { sub(/[^\/]*$/, "", p); return p }
    function base_of(p) { sub(/.*\//, "", p); return p }
    function ends(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
    # Plain names: a basename that is itself a path token gets the exact test;
    # anything else keeps the substring test rather than losing coverage.
    FILENAME == plainf {
      if ($0 == "") next
      b = base_of($0)
      if (b ~ /^[A-Za-z0-9_.-]+$/) want[b] = 1
      else loose[b] = 1
      next
    }
    FILENAME == resf {
      if ($0 == "") next
      b = base_of($0)
      rt[b, ++nrt[b]] = $0
      next
    }
    FILENAME == allf {
      b = base_of($0)
      if (b in nrt) same[b, ++nsame[b]] = $0
      next
    }
    # uniq_suffix: the shortest path suffix, two components or more, that no
    # other file of the same basename ends in; empty when there is none.
    function uniq_suffix(t,   n, pa, k, j, suf, b, i, o, clash) {
      n = split(t, pa, "/")
      b = pa[n]
      for (k = 2; k <= n; k++) {
        suf = pa[n - k + 1]
        for (j = n - k + 2; j <= n; j++) suf = suf "/" pa[j]
        clash = 0
        for (i = 1; i <= nsame[b]; i++) {
          o = same[b, i]
          if (o != t && (o == suf || ends(o, "/" suf))) { clash = 1; break }
        }
        if (!clash) return suf
      }
      return ""
    }
    # resolves: does path token pt, written in file namer, mean target t? Any
    # mention from the directory of t does. A bare name does from a directory
    # above t when no other file of that name sits below that directory. A path
    # does when it ends in the shortest unique suffix of t, or in the path of t
    # relative to a directory below the root holding both files, when that
    # relative path has a directory in it ($SCRIPT_DIR/lib/x.sh,
    # $PLUGIN_DIR/skills/<s>/SKILL.md).
    function resolves(namer, pt, t,   u, a, i, b, rel) {
      a = dir_of(namer)
      if (a == dir_of(t)) return 1
      b = base_of(t)
      if (!index(pt, "/")) {
        if (a != "" && index(t, a) != 1) return 0
        for (i = 1; i <= nsame[b]; i++)
          if (same[b, i] != t && (a == "" || index(same[b, i], a) == 1)) return 0
        return 1
      }
      if (!(t in usuf)) usuf[t] = uniq_suffix(t)
      u = usuf[t]
      if (u != "" && (pt == u || ends(pt, "/" u))) return 1
      for (; a != ""; sub(/[^\/]*\/$/, "", a)) {
        if (index(t, a) != 1) continue
        rel = substr(t, length(a) + 1)
        if (index(rel, "/") && (pt == rel || ends(pt, "/" rel))) return 1
      }
      return 0
    }
    # runs_or_loads: R4. An interpreter or process API on the line, or a path
    # to the file.
    function runs_or_loads(name, n,   j) {
      if (exec_line) return 1
      for (j = 1; j <= n; j++) if (ends(ptok[j], "/" name)) return 1
      return 0
    }
    function keep(path, name, n) {
      key = path SUBSEP name
      if (!(key in kept)) { kept[key] = 0; order[++nkept] = key }
      if (!kept[key] && runs_or_loads(name, n)) kept[key] = 1
    }
    # comment_only: a whole-line comment names nothing (COMMENTS in the header),
    # except a shellcheck source directive and a JSDoc type import.
    function comment_only(path, text) {
      if (path ~ /\.(js|mjs|cjs)$/)
        return text ~ /^[ \t]*(\/\/|\/\*|\*([ \t\/]|$))/ && text !~ /@import|import\(/
      if (text ~ /^[ \t]*#[ \t]*shellcheck[ \t]+source=/) return 0
      return text ~ /^[ \t]*#/
    }
    {
      i = index($0, ":")
      # No separator means no path: git grep says "Binary file X matches" that way.
      if (i == 0) next
      path = substr($0, 1, i - 1)
      text = substr($0, i + 1)
      if (comment_only(path, text)) next
      # A word, not an extension: the `.sh` of `x.sh` is no interpreter.
      exec_line = text ~ /(^|[^A-Za-z0-9_.-])(bash|sh|zsh|python3?|node|deno|pwsh|powershell|uv|npx|source|subprocess|Popen|check_output|check_call|spawn[A-Za-z0-9_]*|exec[A-Za-z0-9_]*|execa|child_process|Start-Process|Invoke-Expression)([^A-Za-z0-9_-]|$)/
      # Path tokens. A leading `.` stays: `./x`, `../x` and `.claude-plugin/x`
      # are paths, not punctuation.
      np = split(text, ptok, /[^A-Za-z0-9_.\/-]+/)
      for (j = 1; j <= np; j++) {
        sub(/\.+$/, "", ptok[j])
        sub(/^[-+=?]+/, "", ptok[j])
        b = base_of(ptok[j])
        if (!(b in nrt)) continue
        for (k = 1; k <= nrt[b]; k++)
          if (rt[b, k] != path && resolves(path, ptok[j], rt[b, k])) {
            key = path SUBSEP rt[b, k]
            if (!(key in rhit)) { rhit[key] = 1; print "r\t" path "\t" rt[b, k] }
          }
      }
      n = split(text, tok, /[^A-Za-z0-9_.-]+/)
      for (j = 1; j <= n; j++) {
        t = tok[j]
        if (t == "") continue
        if (t in want) { keep(path, t, np); continue }
        sub(/\.+$/, "", t)
        if (t in want) { keep(path, t, np); continue }
        sub(/^[-+=?.]+/, "", t)
        if (t in want) keep(path, t, np)
      }
      for (name in loose)
        if (index(text, name) > 0) {
          key = path SUBSEP name
          if (!(key in kept)) order[++nkept] = key
          kept[key] = 1
        }
    }
    END {
      for (k = 1; k <= nkept; k++) {
        split(order[k], kv, SUBSEP)
        print "p\t" kv[1] "\t" kv[2] "\t" kept[order[k]]
      }
    }
  ' "$1" "$2" "$WORK_DIR/all-files" "$3" >"$4"
}

# py_hits <py-frontier> <hits> -> PYTHON IMPORTS: append one
#   r<TAB><importer><TAB><frontier module>
# line for every .py whose import line imports a frontier module, read from the
# import lines build_tree_index listed.
py_hits() {
  awk -v front="$1" -v allf="$WORK_DIR/all-files" '
    function dir_of(p) { sub(/[^\/]*$/, "", p); return p }
    function root_of(p,   c) { split(p, c, "/"); return c[1] == "plugins" ? "plugins/" c[2] "/" : c[1] "/" }
    function ends(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
    # The module a file is: foo for foo.py, pkg for pkg/__init__.py.
    function modname(p) {
      if (p ~ /(^|\/)__init__\.py$/) { p = dir_of(p); sub(/\/$/, "", p) }
      sub(/.*\//, "", p)
      sub(/\.py$/, "", p)
      return p
    }
    # imports: does dotted name D, imported in P, mean module file t? From the
    # directory t is imported from, or below it (a tests/ directory); by a
    # dotted path that spells t; or anywhere in the same plugin when t is the
    # only module of that name there.
    function imports(P, D, t, m,   home, pd, path) {
      home = dir_of(t)
      if (t ~ /(^|\/)__init__\.py$/) { sub(/\/$/, "", home); home = dir_of(home) }
      pd = dir_of(P)
      if (pd == home || (home != "" && index(pd, home) == 1)) return 1
      if (index(D, ".")) {
        path = D
        gsub(/\./, "/", path)
        if (ends("/" t, "/" path ".py") || ends("/" t, "/" path "/__init__.py")) return 1
      }
      return root_of(P) == root_of(t) && cnt[root_of(t), m] == 1
    }
    function cand(P, D,   m, k, t) {
      m = D
      sub(/.*\./, "", m)
      for (k = 1; k <= nt[m]; k++) {
        t = tg[m, k]
        if (t != P && imports(P, D, t, m) && !((P SUBSEP t) in seen)) {
          seen[P, t] = 1
          print "r\t" P "\t" t
        }
      }
    }
    FILENAME == front { if ($0 != "") { m = modname($0); tg[m, ++nt[m]] = $0 } next }
    FILENAME == allf { if ($0 ~ /\.py$/) cnt[root_of($0), modname($0)]++; next }
    {
      i = index($0, ":")
      if (i == 0) next
      P = substr($0, 1, i - 1)
      s = substr($0, i + 1)
      sub(/#.*/, "", s)
      gsub(/[()\\]/, " ", s)
      if (s ~ /^[ \t]*from[ \t]/) {
        sub(/^[ \t]*from[ \t]+/, "", s)
        base = s
        sub(/[ \t].*/, "", base)
        sub(/^[^ \t]+[ \t]+import[ \t]+/, "", s)
        sub(/^\.+/, "", base)
        if (base != "") cand(P, base)
      } else {
        sub(/^[ \t]*import[ \t]+/, "", s)
        base = ""
      }
      n = split(s, ys, /,/)
      for (k = 1; k <= n; k++) {
        y = ys[k]
        sub(/^[ \t]+/, "", y)
        sub(/[ \t].*/, "", y)
        if (y !~ /^[A-Za-z_][A-Za-z0-9_.]*$/) continue
        cand(P, base == "" ? y : base "." y)
      }
    }
  ' "$1" "$WORK_DIR/all-files" "$WORK_DIR/py-imports" >>"$2"
}

# colocated_suites <path> -> every sibling suite covering it, one per line.
# PLURAL on purpose: a .py can carry a co-located test_<stem>.py and a
# wrapping <stem>.test.sh at once, and returning one under-selects.
colocated_suites() {
  local p="$1" stem dir base candidate
  if is_suite_path "$p"; then
    printf '%s\n' "$p"
    return 0
  fi
  stem="${p%.*}"
  dir="${p%/*}"
  [[ "$dir" == "$p" ]] && dir="."
  base="${stem##*/}"
  local -a candidates=(
    "$stem.test.sh"
    "$stem.test.js"
    "$stem.test.mjs"
    "$stem.Tests.ps1"
    "$dir/test_$base.py"
    # A Python suite reaches its subject with `import <module>`, which never
    # spells the filename, so the tests/ form has to be a path rule.
    "$dir/tests/test_$base.py"
  )
  [[ "$base" == *-* ]] && candidates+=(
    "$dir/test_${base//-/_}.py"
    "$dir/tests/test_${base//-/_}.py"
  )
  for candidate in ${candidates[@]+"${candidates[@]}"}; do
    [[ -f "$candidate" ]] && printf '%s\n' "$candidate"
  done
  return 0
}

# select_for <changed-path> -> populate SUITES, and set SEED_HITS to the number
# of suites THIS seed reached. The count comes back through a global: a command
# substitution would run the walk in a subshell and lose every SUITES entry.
select_for() {
  local seed="$1"
  local -a frontier=() next=()
  local p b sib copy line kind hit_path hit_name hit_x grep_rc
  local origin_family hit_family hop_state
  # PATTERN_ORIGIN maps a plain basename back to the ecosystem of the file that
  # contributed it ('*' when two families contributed it, which over-selects),
  # and PATTERN_CROSSED records whether that file had spent its transition.
  local -A PATTERN_ORIGIN=() PATTERN_CROSSED=() CROSSED=()
  # PER SEED, not shared: a shared visited set made a changed file another
  # seed had walked past look unmapped.
  local -A VISITED=()
  SEED_HITS=0

  frontier=("$seed")
  # R5: a sync source seeds every copy the manifest declares.
  if [[ -n "${SYNC_SRC_COPIES[$seed]:-}" ]]; then
    while IFS= read -r copy; do
      [[ -n "$copy" ]] && frontier+=("$copy")
    done <<<"${SYNC_SRC_COPIES[$seed]}"
  fi
  # R6: a sync script pulls in whatever its sources pull in.
  if [[ -n "${SYNC_SCRIPT_SRC[$seed]:-}" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      frontier+=("$line")
      while IFS= read -r copy; do
        [[ -n "$copy" ]] && frontier+=("$copy")
      done <<<"${SYNC_SRC_COPIES[$line]:-}"
    done <<<"${SYNC_SCRIPT_SRC[$seed]}"
  fi

  while [[ ${#frontier[@]} -gt 0 ]]; do
    : >"$WORK_DIR/patterns"
    : >"$WORK_DIR/plain"
    : >"$WORK_DIR/resolve"
    : >"$WORK_DIR/pyfront"
    next=()
    for p in "${frontier[@]}"; do
      [[ -n "${VISITED[$p]:-}" ]] && continue
      VISITED["$p"]=1
      [[ "$p" == *.py ]] && printf '%s\n' "$p" >>"$WORK_DIR/pyfront"
      # R1/R2
      while IFS= read -r sib; do
        [[ -n "$sib" ]] || continue
        if [[ "$sib" == "$p" ]]; then
          add_suite "$sib" "changed suite" || true
        else
          add_suite "$sib" "co-located with $p" || true
        fi
      done < <(colocated_suites "$p")
      # R7. The suite path is joined from two pieces so this file never carries
      # its basename as one token, which would make this file name the suite.
      case "$p" in
      plugins/autonomy/reference/*)
        add_suite "scripts/validate-plugin-contracts"".test.sh" \
          "path class: autonomy reference/ is gated by the contract validator" || true
        ;;
      *) ;;
      esac
      b="${p##*/}"
      # MANIFESTS: no mention reaches a suite from a manifest or changelog.
      [[ "$MANIFEST_BASENAMES" == *" $b "* ]] && continue
      printf '%s\n' "$b" >>"$WORK_DIR/patterns"
      if [[ "$STRUCTURAL_BASENAMES" == *" $b "* ]] ||
        [[ -n "${AMBIGUOUS[$b]:-}" && -z "${SYNC_MEMBER[$p]:-}" ]]; then
        printf '%s\n' "$p" >>"$WORK_DIR/resolve"
        continue
      fi
      lang_family "$p"
      origin_family="$LANG_FAMILY"
      if [[ -z "${PATTERN_ORIGIN[$b]:-}" ]]; then
        PATTERN_ORIGIN["$b"]="$origin_family"
        PATTERN_CROSSED["$b"]="${CROSSED[$p]:-0}"
      else
        [[ "${PATTERN_ORIGIN[$b]}" == "$origin_family" ]] || PATTERN_ORIGIN["$b"]='*'
        # Any contributor that has NOT yet crossed wins: over-select.
        [[ "${CROSSED[$p]:-0}" == "0" ]] && PATTERN_CROSSED["$b"]=0
      fi
      printf '%s\n' "$p" >>"$WORK_DIR/plain"
    done

    [[ -s "$WORK_DIR/patterns" ]] || break

    # One batched reverse lookup per level, in the two stages the header
    # describes. The hits go through a FILE rather than a process substitution
    # so a git ERROR (exit >= 2) is not read as NO MATCH (exit 1): both would
    # come back as "no dependents", an under-selection at exit 0. Every
    # extension lang_family() names is searched, or a family it classifies
    # would be under-covered while looking supported.
    grep_rc=0
    git grep --untracked -F -f "$WORK_DIR/patterns" \
      -- '*.sh' '*.bash' '*.js' '*.mjs' '*.cjs' '*.py' '*.ps1' '*.psm1' \
      >"$WORK_DIR/matched-lines" || grep_rc=$?
    if [[ "$grep_rc" -gt 1 ]]; then
      echo "error: 'git grep' failed (exit $grep_rc) resolving dependents of the current level." >&2
      echo "       Refusing to continue: an unreadable reverse lookup silently UNDER-selects, and" >&2
      echo "       under-selection is reported as success by everything downstream." >&2
      exit 2
    fi
    # Fatal for the same reason: a filter that dies mid-stream hands the walk a
    # TRUNCATED hit set.
    if ! token_hits "$WORK_DIR/plain" "$WORK_DIR/resolve" "$WORK_DIR/matched-lines" "$WORK_DIR/hits" ||
      { [[ -s "$WORK_DIR/pyfront" ]] && ! py_hits "$WORK_DIR/pyfront" "$WORK_DIR/hits"; }; then
      echo "error: the token filter over the reverse lookup failed on the current level." >&2
      echo "       Refusing to continue: a partial filter silently UNDER-selects, and" >&2
      echo "       under-selection is reported as success by everything downstream." >&2
      exit 2
    fi
    while IFS=$'\t' read -r kind hit_path hit_name hit_x; do
      [[ -n "$hit_path" ]] || continue
      if [[ "$kind" == r ]]; then
        # A mention that resolves to an ambiguous or structural file is a real
        # reference to it, from any language, and spends no transition.
        if is_suite_path "$hit_path"; then
          add_suite "$hit_path" "references ${hit_name##*/} (resolves to $hit_name)" || true
        elif [[ -z "${VISITED[$hit_path]:-}" ]]; then
          CROSSED["$hit_path"]=0
          next+=("$hit_path")
        fi
        continue
      fi
      lang_family "$hit_path"
      hit_family="$LANG_FAMILY"
      origin_family="${PATTERN_ORIGIN[$hit_name]:-*}"
      if [[ "$origin_family" == '*' || "$hit_family" == "$origin_family" ]]; then
        # R3: same language, spends no transition.
        hop_state="${PATTERN_CROSSED[$hit_name]:-0}"
      elif [[ "$origin_family" == ext:* ]]; then
        # R4: data reaches code of any language, and spends no transition.
        hop_state=0
      elif [[ "$hit_x" != 1 ]]; then
        # R4: another language that neither runs nor loads the file.
        continue
      elif ! is_suite_path "$hit_path" && [[ "${PATTERN_CROSSED[$hit_name]:-0}" == 1 ]]; then
        # R4: a second transition. A suite that runs or loads the file is still
        # taken: the budget bounds the walk, not the suites it ends in.
        continue
      else
        hop_state=1
      fi
      if is_suite_path "$hit_path"; then
        add_suite "$hit_path" "references $hit_name" || true
        continue
      fi
      [[ -n "${VISITED[$hit_path]:-}" ]] && continue
      # AGGREGATE, never assign: one path can be hit by several patterns in one
      # round that disagree about whether its chain has crossed, and the most
      # permissive state wins, whatever order git grep printed them in.
      if [[ "${CROSSED[$hit_path]:-1}" != "0" ]]; then
        CROSSED["$hit_path"]="$hop_state"
      fi
      next+=("$hit_path")
    done <"$WORK_DIR/hits"

    frontier=(${next[@]+"${next[@]}"})
  done
}

# check_scope_globs -> exit 2 when a declared glob matches no file of the tree:
# it declares nothing, so the suite misses the changes it reads. Run when the
# scopes list itself changes, which is when a glob is written or goes stale.
check_scope_globs() {
  [[ ${#SCOPE_GLOBS[@]} -gt 0 ]] || return 0
  printf '%s\n' "${SCOPE_GLOBS[@]}" | awk '
    # The glob dialect of the lists: `*` any run of characters, `/` included.
    function to_regex(g,   r, i, c) {
      r = "^"
      for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*") r = r ".*"
        else if (c == "?") r = r "."
        else if (index(".+(){}|^$\\", c)) r = r "\\" c
        else r = r c
      }
      return r "$"
    }
    FNR == NR { if (!($0 in want)) { want[$0] = to_regex($0); order[++n] = $0 } next }
    { for (g in want) if (!(g in hit) && $0 ~ want[g]) hit[g] = 1 }
    END { for (i = 1; i <= n; i++) if (!(order[i] in hit)) { print order[i]; bad = 1 } exit bad }
  ' - "$WORK_DIR/all-files" >"$WORK_DIR/stale-globs" && return 0
  echo "error: $SCOPES_LIST declares globs that match no file of the tree:" >&2
  sed 's/^/  - /' "$WORK_DIR/stale-globs" >&2
  exit 2
}

# select_scoped <changed-path> -> R8: add every suite whose declared test-scope
# matches the path, counting each as a hit of the current seed.
select_scoped() {
  local p="$1" i
  for i in "${!SCOPE_GLOBS[@]}"; do
    # shellcheck disable=SC2053 # the right-hand side is a glob pattern by design.
    [[ "$p" == ${SCOPE_GLOBS[i]} ]] || continue
    add_suite "${SCOPE_SUITES[i]}" "test-scope ${SCOPE_GLOBS[i]}" || true
  done
}

# ---------------------------------------------------------------------------
# No-suite classification
# ---------------------------------------------------------------------------

declare -a NO_SUITE_PATTERNS=()
load_no_suite_patterns() {
  if [[ ! -f "$NO_SUITE_LIST" ]]; then
    echo "error: missing $NO_SUITE_LIST — the no-suite classification cannot be applied," >&2
    echo "       and without it every doc and manifest change would report as unmapped." >&2
    exit 2
  fi
  # `inline`: these are glob patterns over repo paths, never regexes, so a `#`
  # anywhere on the line is a comment (scripts/lib/read-list.sh owns the two
  # comment families and why they must stay distinct).
  read_list::into NO_SUITE_PATTERNS "$NO_SUITE_LIST" --comments inline || exit 2
  if [[ ${#NO_SUITE_PATTERNS[@]} -eq 0 ]]; then
    echo "error: $NO_SUITE_LIST has no active patterns." >&2
    exit 2
  fi
}

is_no_suite() {
  local p="$1" pat
  for pat in "${NO_SUITE_PATTERNS[@]}"; do
    # shellcheck disable=SC2053 # the right-hand side is a glob pattern by design.
    [[ "$p" == $pat ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Changed-file resolution
# ---------------------------------------------------------------------------

changed_from_diff() {
  local base="" mb
  # An explicit --base must resolve or be an error naming it, never a silent
  # fall-through to origin/main that reports suites for a diff nobody asked
  # for. The fallback ladder is shared with the checker gates.
  if [[ -n "$base_ref" ]]; then
    if ! changed_files::verify_base "$base_ref"; then
      echo "error: base ref '$base_ref' does not resolve to a commit." >&2
      exit 2
    fi
    base="$base_ref"
  elif ! changed_files::resolve_base base; then
    echo "error: no diff base resolved (tried --base, origin/main, origin/master, main, master)." >&2
    echo "       Pass --base <ref>, or give explicit paths." >&2
    exit 2
  fi
  # The WORKING TREE against the merge base: uncommitted edits count, and so
  # does nothing that landed on the base branch meanwhile. Mid-merge, the
  # MERGE_HEAD commits join the merge-base computation, so the incoming side's
  # files are not charged to this change.
  local merge_head_file=""
  local -a merge_heads=()
  merge_head_file="$(git rev-parse --git-path MERGE_HEAD 2>/dev/null)" || merge_head_file=""
  if [[ -n "$merge_head_file" && -f "$merge_head_file" ]]; then
    mapfile -t merge_heads <"$merge_head_file"
  fi
  mb="$(git merge-base "$base" HEAD "${merge_heads[@]}" 2>/dev/null)" || mb="$base"
  # Every failure is fatal, never an empty list, which downstream reads as
  # "nothing to select, exit 0". This runs in the CURRENT shell (see the call
  # site) so these exits are the script's.
  if ! git diff --name-only "$mb" --; then
    echo "error: 'git diff --name-only $mb' failed; refusing to report an empty change set." >&2
    exit 2
  fi
  if ! git ls-files --others --exclude-standard; then
    echo "error: 'git ls-files --others' failed; refusing to report an empty change set." >&2
    exit 2
  fi
}

# --print-fanout exists so the DERIVATION itself is inspectable and testable:
# the copy set for a shared source must equal what the sync manifest declares
# right now, not what someone once transcribed into this file.
if [[ -n "$print_fanout" ]]; then
  build_sync_map
  print_fanout="${print_fanout#./}"
  # Presence, not non-emptiness: a canonical-only src has an empty copy set.
  if [[ -z "${SYNC_SRC_COPIES[$print_fanout]+set}" ]]; then
    echo "error: $print_fanout is not the src of any scripts/sync-*.sh manifest." >&2
    exit 2
  fi
  printf '%s' "${SYNC_SRC_COPIES[$print_fanout]}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Replay
# ---------------------------------------------------------------------------

# replay_select <out-prefix> <tree> <selector> <no-suite-list> <scopes-list>
#               [<flag>...] -- <path>...
# One selection in the replay tree, through a fresh process. Writes
# <out-prefix>.sel (`<suite>\t<reason>`) and <out-prefix>.unmapped, and fails
# loud on any exit but 0, because a broken selection counted as an empty one
# would understate the side it ran for.
replay_select() {
  local out="$1" tree="$2" sel="$3" list="$4" scopes="$5" rc=0
  shift 5
  AFFECTED_TESTS_ROOT="$tree" AFFECTED_TESTS_NO_SUITE="$list" AFFECTED_TESTS_SCOPES="$scopes" \
    bash "$sel" --explain --allow-unmapped "$@" >/dev/null 2>"$out.err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "error: the selector $sel failed (exit $rc) on a replayed commit:" >&2
    cat "$out.err" >&2
    exit 2
  fi
  awk '/^select: / { sub(/^select: /, ""); i = index($0, "  ("); print substr($0, 1, i - 1) "\t" substr($0, i + 3, length($0) - i - 3) }' \
    "$out.err" | sort >"$out.sel"
  awk '/^UNMAPPED:/ { f = 1; next } f && /^  - / { sub(/^  - /, ""); print; next } { f = 0 }' "$out.err" >"$out.unmapped"
}

run_replay() {
  local tree="$WORK_DIR/replay-tree" against="$WORK_DIR/against" against_scopes=""
  local c subject n_new n_old u_new u_old
  local -a commits=() changed=() against_flags=()
  if ! git rev-list --first-parent --reverse "$replay_range" >"$WORK_DIR/commits"; then
    echo "error: '$replay_range' is not a revision range git can list." >&2
    exit 2
  fi
  mapfile -t commits <"$WORK_DIR/commits"
  if [[ ${#commits[@]} -eq 0 ]]; then
    echo "error: '$replay_range' holds no commits to replay." >&2
    exit 2
  fi
  # This tree's rules travel with the replay: its no-suite and scopes lists.
  cp "$NO_SUITE_LIST" "$WORK_DIR/replay-no-suite" || exit 2
  cp "$SCOPES_LIST" "$WORK_DIR/replay-scopes" || exit 2
  if ! git clone -q --shared --no-checkout . "$tree"; then
    echo "error: could not make the scratch clone for the replay." >&2
    exit 2
  fi
  if [[ -n "$against_ref" ]]; then
    # <ref>'s selector, its scripts/lib/ and its lists, pointed at the replay
    # tree through AFFECTED_TESTS_ROOT. A selector without that override gets
    # its one `cd` line rewritten; one with neither form cannot be pointed.
    mkdir -p "$against/scripts" || exit 2
    if ! git show "$against_ref:scripts/affected-tests.sh" >"$against/selector.orig" ||
      ! git archive "$against_ref" scripts/lib | tar -x -C "$against" ||
      ! git show "$against_ref:scripts/affected-tests-no-suite.txt" >"$against/no-suite.txt"; then
      echo "error: could not read the selector, its scripts/lib/ or its no-suite list at '$against_ref'." >&2
      exit 2
    fi
    awk '$0 == "cd \"$SCRIPT_DIR/..\" || exit 2" { print "cd \"${AFFECTED_TESTS_ROOT:-$SCRIPT_DIR/..}\" || exit 2"; n++; next }
      index($0, "AFFECTED_TESTS_ROOT") { n++ } { print } END { exit n ? 0 : 1 }' \
      "$against/selector.orig" >"$against/scripts/affected-tests.sh" || {
      echo "error: the selector at '$against_ref' cannot be pointed at another tree." >&2
      exit 2
    }
    grep -q -- '--with-always)' "$against/scripts/affected-tests.sh" && against_flags+=(--with-always)
    git show "$against_ref:scripts/affected-tests-always.txt" >"$against/always.txt" 2>/dev/null ||
      rm -f "$against/always.txt"
    # A selector that reads a scopes list gets <ref>'s own.
    if git show "$against_ref:scripts/affected-tests-scopes.txt" >"$against/scopes.txt" 2>/dev/null; then
      against_scopes="$against/scopes.txt"
    fi
  fi

  for c in "${commits[@]}"; do
    git -C "$tree" -c advice.detachedHead=false checkout -q --detach "$c" || exit 2
    subject="$(git -C "$tree" log -1 --format=%s "$c")" || exit 2
    if ! git -C "$tree" diff --no-renames --name-only "$c^" "$c" >"$WORK_DIR/replay-changed"; then
      echo "error: could not diff $c against its parent." >&2
      exit 2
    fi
    mapfile -t changed <"$WORK_DIR/replay-changed"
    [[ ${#changed[@]} -gt 0 ]] || continue
    replay_select "$WORK_DIR/new" "$tree" "$SELF" "$WORK_DIR/replay-no-suite" "$WORK_DIR/replay-scopes" \
      -- "${changed[@]}"
    n_new=$(grep -c . "$WORK_DIR/new.sel")
    u_new=$(grep -c . "$WORK_DIR/new.unmapped")
    if [[ -z "$against_ref" ]]; then
      printf 'commit %s %s %s  %s\n' "$c" "$n_new" "$u_new" "$subject"
      sed 's/^/  unmapped /' "$WORK_DIR/new.unmapped"
      awk -F '\t' '{ print "  " $1 "  (" $2 ")" }' "$WORK_DIR/new.sel"
      printf '%s\t%s\t-\t%s\t-\n' "$c" "$n_new" "$u_new" >>"$WORK_DIR/replay-counts"
      continue
    fi
    # The always list as <ref> has it, narrowed to the suites this commit has:
    # its selector refuses an entry naming no suite.
    if [[ -f "$against/always.txt" ]]; then
      awk -v root="$tree" '/^#/ || NF == 0 { print; next } { if ((getline _ < (root "/" $1)) >= 0) print; close(root "/" $1) }' \
        "$against/always.txt" >"$WORK_DIR/always-now"
      export AFFECTED_TESTS_ALWAYS="$WORK_DIR/always-now"
    fi
    replay_select "$WORK_DIR/old" "$tree" "$against/scripts/affected-tests.sh" "$against/no-suite.txt" \
      "$against_scopes" ${against_flags[@]+"${against_flags[@]}"} -- "${changed[@]}"
    n_old=$(grep -c . "$WORK_DIR/old.sel")
    u_old=$(grep -c . "$WORK_DIR/old.unmapped")
    printf 'commit %s %s %s %s %s  %s\n' "$c" "$n_new" "$n_old" "$u_new" "$u_old" "$subject"
    sed 's/^/  unmapped /' "$WORK_DIR/new.unmapped"
    awk -F '\t' 'FILENAME == ARGV[1] { n[$1] = $2; next } { o[$1] = $2 }
      END {
        for (s in n) if (!(s in o)) print "  + " s "  (" n[s] ")"
        for (s in o) if (!(s in n)) print "  - " s "  (" o[s] ")"
      }' "$WORK_DIR/new.sel" "$WORK_DIR/old.sel" | sort -k2
    printf '%s\t%s\t%s\t%s\t%s\n' "$c" "$n_new" "$n_old" "$u_new" "$u_old" >>"$WORK_DIR/replay-counts"
  done

  [[ -s "$WORK_DIR/replay-counts" ]] || {
    echo "Replayed ${#commits[@]} commit(s); none changed a file." >&2
    return 0
  }
  awk -F '\t' -v against="$against_ref" '
    function pct(a, n, q,   i) { i = int(q * n); if (i >= n) i = n - 1; return a[i + 1] }
    function sortn(a, n,   i, j, t) { for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t } }
    { nn[++c] = $2; tn += $2; un += ($4 > 0); if (against != "") { no[c] = $3; to += $3; uo += ($5 > 0) } }
    END {
      sortn(nn, c)
      printf "replay: %d commit(s); this selector: suites per commit p50 %d, p95 %d, max %d, total %d; commits with an unmapped file %d\n", c, pct(nn, c, .5), pct(nn, c, .95), nn[c], tn, un
      if (against != "") {
        sortn(no, c)
        printf "replay: %s: suites per commit p50 %d, p95 %d, max %d, total %d; commits with an unmapped file %d\n", against, pct(no, c, .5), pct(no, c, .95), no[c], to, uo
      }
    }' "$WORK_DIR/replay-counts" >&2
}

if [[ -n "$replay_range" ]]; then
  run_replay
  exit 0
fi

declare -a changed=()
if [[ ${#explicit_paths[@]} -gt 0 ]]; then
  for p in "${explicit_paths[@]}"; do
    p="${p#./}"
    # Every rule is repo-relative, and so is every sync-manifest key. An
    # absolute path that stayed absolute would miss them and fall through to a
    # broad no-suite pattern: success with no suites. Normalize what can be
    # normalized and refuse the rest out loud.
    case "$p" in
    "$PWD"/*) p="${p#"$PWD"/}" ;;
    /* | [A-Za-z]:[/\\]*)
      echo "error: '$p' is absolute and does not sit under this repository as spelled." >&2
      echo "       Pass repository-relative paths (Git Bash spells this checkout '$PWD')." >&2
      exit 2
      ;;
    *) ;;
    esac
    changed+=("$p")
  done
else
  # Run the producer in the CURRENT shell so its fatal exits are the script's.
  changed_from_diff >"$WORK_DIR/changed.raw"
  # Checked: a failing `sort` read from a process substitution would yield an
  # EMPTY change set at exit 0.
  if ! sort -u "$WORK_DIR/changed.raw" >"$WORK_DIR/changed"; then
    echo "error: sorting the changed-file list failed; refusing to report an empty change set." >&2
    exit 2
  fi
  mapfile -t changed <"$WORK_DIR/changed"
fi

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "No changed files against the base ref; nothing to select." >&2
  exit 0
fi

build_sync_map
load_no_suite_patterns
build_tree_index

declare -a NO_SUITE_FILES=()
for f in "${changed[@]}"; do
  [[ -n "$f" ]] || continue
  [[ "$f" == "$SCOPES_LIST" ]] && check_scope_globs
  select_for "$f"
  select_scoped "$f"
  if [[ "$SEED_HITS" -eq 0 ]]; then
    if is_no_suite "$f"; then
      NO_SUITE_FILES+=("$f")
    elif [[ ! -e "$f" ]]; then
      # A deletion that maps to nothing needs no suite: it has no content left
      # to cover, and anything that still referenced it selects through its own
      # changed path or a suite naming the dead path.
      DELETED+=("$f")
    else
      UNMAPPED+=("$f")
    fi
  fi
done

if [[ ${#NO_SUITE_FILES[@]} -gt 0 && "$explain" -eq 1 ]]; then
  for f in "${NO_SUITE_FILES[@]}"; do
    echo "no-suite: $f (recorded in $NO_SUITE_LIST; a non-shell CI lane covers it)" >&2
  done
fi

if [[ ${#DELETED[@]} -gt 0 ]]; then
  for f in "${DELETED[@]}"; do
    echo "deleted: $f (no longer exists and no surviving suite names it; nothing left to cover)" >&2
  done
fi

corpus_used=0
if [[ ${#UNMAPPED[@]} -gt 0 ]]; then
  echo "UNMAPPED: ${#UNMAPPED[@]} changed file(s) map to no test suite:" >&2
  for f in "${UNMAPPED[@]}"; do
    echo "  - $f" >&2
  done
  echo "This is NOT 'nothing to run' — it is 'this tool does not know what covers these'." >&2
  echo "Fix one of: add a co-located <stem>.test.sh; make a suite name the file; declare a" >&2
  echo "test-scope on the suite that reads it; or record the path class in $NO_SUITE_LIST" >&2
  echo "with the CI lane that does cover it." >&2
  if [[ "$unmapped_corpus" -eq 1 ]]; then
    declare -A CORPORA=()
    for f in "${UNMAPPED[@]}"; do
      lang_family "$f"
      case "$LANG_FAMILY" in
      py | node | ps) CORPORA["$LANG_FAMILY"]=1 ;;
      *) CORPORA[sh]=1 ;;
      esac
    done
    awk -v want=" ${!CORPORA[*]} " '
      { b = $0; sub(/.*\//, "", b) }
      /\.test\.sh$/ { e = "sh" }
      /\.test\.m?js$/ { e = "node" }
      /\.Tests\.ps1$/ { e = "ps" }
      b ~ /^test_.*\.py$/ { e = "py" }
      e != "" && index(want, " " e " ") { print e "\t" $0 }
      { e = "" }' "$WORK_DIR/all-files" >"$WORK_DIR/corpus"
    while IFS=$'\t' read -r lang suite; do
      add_suite "$suite" "unmapped-corpus: the $lang corpus of an unmapped file" || true
    done <"$WORK_DIR/corpus"
    echo "Selecting the whole corpus of each unmapped file's language under --unmapped-corpus: ${!CORPORA[*]}." >&2
    corpus_used=1
  elif [[ "$allow_unmapped" -eq 0 ]]; then
    echo "Re-run with --allow-unmapped to proceed anyway." >&2
    exit 1
  else
    echo "Proceeding under --allow-unmapped." >&2
  fi
fi

# `${!SUITES[@]}` cannot carry a `+` default-guard: bash parses `${!NAME...}` as
# an indirect reference and rejects the expanded key list as a variable name.
declare -a selected=()
if [[ ${#SUITES[@]} -gt 0 ]]; then
  # Checked, and read from a file: a failing `sort` here would empty a
  # NON-EMPTY selection and report "every changed file is a no-suite class".
  if ! printf '%s\n' "${!SUITES[@]}" | sort -u >"$WORK_DIR/selected"; then
    echo "error: sorting the selected-suite list failed; refusing to report an empty selection" >&2
    echo "       when ${#SUITES[@]} suite(s) were selected." >&2
    exit 2
  fi
  mapfile -t selected <"$WORK_DIR/selected"
fi

if [[ ${#selected[@]} -eq 0 ]]; then
  echo "No suites selected (every changed file is a recorded no-suite class or a deletion)." >&2
  exit 0
fi

# The partition happens HERE, after the unmapped check and the sort, so every
# leg derives the same full selection from the same diff and keeps its own
# slice; partitioning the changed files would let the unmapped check fire on
# only one leg.
if [[ "$shard_total" -gt 1 ]]; then
  declare -a leg=()
  for ((si = shard_index; si < ${#selected[@]}; si += shard_total)); do
    leg+=("${selected[$si]}")
  done
  echo "shard: leg $shard_index of $shard_total keeps ${#leg[@]} of ${#selected[@]} selected suite(s)." >&2
  selected=("${leg[@]}")
  if [[ ${#selected[@]} -eq 0 ]]; then
    echo "This leg has no suites to run; the other legs carry the selection." >&2
    exit 0
  fi
fi

if [[ "$explain" -eq 1 ]]; then
  for s in "${selected[@]}"; do
    echo "select: $s  (${SUITES[$s]})" >&2
  done
fi

if [[ "$do_run" -eq 0 ]]; then
  printf '%s\n' "${selected[@]}"
  [[ "$corpus_used" -eq 1 ]] && exit 4
  exit 0
fi

# SEQUENTIAL BY DEFAULT, --jobs N ON REQUEST. On a Windows Git Bash host a
# parallel run was sublinear (the suites are spawn-bound); on a Linux CI runner
# it pays, which is why CI passes a count. --jobs N > 1 hands the selection to
# run-plugin-tests.sh, which owns the worker, the bounded xargs dispatch, the
# per-suite print lock and scripts/run-plugin-tests-serial.txt, the suites that
# must never overlap anything. Three is the proven ceiling on a 4-vCPU runner:
# at four, suites failed by producing empty output from an external command
# (#3694).
#
# Only *.test.sh is executable HERE. The other three ecosystems are run by their
# own lanes, with invocations this script cannot derive from a suite path
# (`python -m unittest` against a named module, `npm test`, `node --test`,
# vitest, Pester), and a guessed runner either errors as though the suite failed
# or exits 0 having run nothing. So they are named and NOT run, and the exit
# code says so.
declare -a runnable=() delegated=()
for s in "${selected[@]}"; do
  case "$s" in
  *.test.sh) runnable+=("$s") ;;
  *) delegated+=("$s") ;;
  esac
done

failed=0
if [[ ${#runnable[@]} -gt 0 ]] && [[ "$jobs" -gt 1 ]]; then
  echo "Running ${#runnable[@]} selected shell suite(s) across up to $jobs job(s)." >&2
  list="$WORK_DIR/selection.txt"
  printf '%s\n' "${runnable[@]}" >"$list"
  bash "$SCRIPT_DIR/run-plugin-tests.sh" --jobs "$jobs" --suites-from "$list" || failed=1
elif [[ ${#runnable[@]} -gt 0 ]]; then
  echo "Running ${#runnable[@]} selected shell suite(s) sequentially." >&2
  for s in "${runnable[@]}"; do
    echo "=== $s ==="
    if bash "$s"; then
      echo "PASS: $s"
    else
      echo "FAIL: $s" >&2
      failed=1
    fi
  done
fi

if [[ ${#delegated[@]} -gt 0 ]]; then
  echo "NOT RUN: ${#delegated[@]} selected suite(s) belong to an ecosystem this" >&2
  echo "runner does not execute. They are SELECTED, not skipped — run each from" >&2
  echo "its own lane:" >&2
  for s in "${delegated[@]}"; do
    echo "  - $s" >&2
  done
fi

if [[ "$failed" -ne 0 ]]; then
  echo "One or more selected suites failed." >&2
  exit 1
fi
if [[ ${#delegated[@]} -gt 0 ]]; then
  echo "${#runnable[@]} shell suite(s) passed or were skipped; ${#delegated[@]} still need their own lane." >&2
  exit 3
fi
if [[ "$corpus_used" -eq 1 ]]; then
  echo "All ${#runnable[@]} selected suites passed or were skipped, including an unmapped file's corpus." >&2
  exit 4
fi
echo "All ${#runnable[@]} selected suites passed or were skipped."
