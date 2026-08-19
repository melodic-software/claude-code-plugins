#!/usr/bin/env bash
# Select the test suites that cover a set of changed files, so a developer can
# run what their change actually affects instead of the whole corpus. Four
# ecosystems carry suites here and each names them differently: shell
# **/*.test.sh, Node **/*.test.js and **/*.test.mjs, Python **/test_*.py, and
# Pester **/*.Tests.ps1.
#
# The full corpus is tens of minutes of wall clock on a Windows box
# (Git Bash pays ~140ms per process spawn, and these suites are spawn-bound),
# which is long enough that nobody runs it locally and regressions reach CI.
#
#   scripts/affected-tests.sh                    list the suites covering the diff vs the base ref
#   scripts/affected-tests.sh --run              ... and run them, sequentially
#   scripts/affected-tests.sh path/a.sh path/b   ... for explicit paths instead of a diff
#   scripts/affected-tests.sh --base <ref>       use <ref> as the diff base (default: origin/main)
#   scripts/affected-tests.sh --explain          report WHY each suite was selected (stderr)
#   scripts/affected-tests.sh --allow-unmapped   downgrade an unmapped file to a warning
#   scripts/affected-tests.sh --print-fanout P   print the copy set DERIVED for shared source P
#
# Exit: 0 selected (or nothing to do); 1 an unmapped changed file, or a failing
# suite under --run; 2 usage or a broken derivation; 3 --run ran every shell
# suite it selected but ALSO selected suites in other ecosystems, whose runner
# it deliberately will not guess (see the --run note at the foot of this file).
#
# DIRECTION: over-selection is safe, under-selection is not. Every rule below is
# deliberately generous — a basename match counts even when it lands in a
# comment — because a suite that runs needlessly costs seconds, while a suite
# that should have run and did not is the regression this tool exists to stop.
#
# FAIL LOUD, NOT OPEN. A changed file that maps to NO suite is an ERROR, not an
# empty selection: "zero suites" reads as "nothing to run" when it actually
# means "nothing here knows what covers this". The only exceptions are the path
# classes recorded in scripts/affected-tests-no-suite.txt, each of which names
# the non-shell CI lane that does cover it. Anything else fails, and
# --allow-unmapped is the one-flag escape.
#
# SELECTION RULES
#   R1 self          a changed suite selects itself, in any ecosystem.
#   R2 co-located    <dir>/<stem>.<ext> selects the sibling suites covering it,
#                    under each ecosystem's OWN naming convention: <stem>.test.sh,
#                    <stem>.test.js, <stem>.test.mjs, <stem>.Tests.ps1, and
#                    <dir>/test_<stem>.py — the last also with `-` folded to `_`,
#                    which is how this repo names the Python suites covering its
#                    hyphenated scripts (check-manifest-duplicate-keys.py ->
#                    test_check_manifest_duplicate_keys.py). EVERY match is taken,
#                    never just the first: a .py can carry both a test_<stem>.py
#                    and a wrapping <stem>.test.sh, and stopping at one
#                    under-selects, which is the unsafe direction.
#   R3 referenced    any SUITE whose text contains the file's basename is a
#                    covering suite (it names the file, so it exercises it). This
#                    rule is a text match and therefore language-agnostic: a
#                    Pester suite dot-sourcing Foo.ps1 and a Node suite importing
#                    foo.js are found exactly the way a shell suite is. Widening
#                    the corpus is what taught it the other three ecosystems; the
#                    rule itself did not change.
#   R4 dependents    any other source file (.sh .bash .js .mjs .cjs .py .ps1
#                    .psm1 — the same set the reverse-lookup pathspec searches,
#                    and the same set lang_family() names; all three move
#                    together or a path is classified into a family nothing ever
#                    greps) whose
#                    text contains the file's basename is a dependent; R2/R3 are
#                    then applied to IT, transitively. This is what carries a lib
#                    change out to the hooks that source it.
#   R5 shared-lib    a file that is the `src=` of a scripts/sync-*.sh selects
#                    every path in that script's `copies=(...)` array, and then
#                    R2/R3/R4 on each copy. The copy set is DERIVED from the sync
#                    manifest on every run, never hardcoded here: the manifests
#                    are what CI's *-sync lanes enforce, so a new carrying plugin
#                    is picked up the moment it exists. Deriving it is the whole
#                    point — a list copied into this file would silently rot, and
#                    the rot would show up as an under-selection.
#   R6 sync script   a changed scripts/sync-*.sh selects its own co-located test
#                    plus everything its `src=` selects, since its failure mode
#                    is the copies drifting from that source.
#
# R3/R4 skip STRUCTURAL basenames — README.md, SKILL.md, plugin.json and the
# like — because those name a repo-wide role rather than one artifact, so a
# basename match carries no coverage signal (SKILL.md alone appears in 20
# unrelated suites). Such files fall through to R2, then to the no-suite list.
#
# The transitive walk has no depth cap WITHIN one ecosystem. It terminates on
# the visited set, and its worst case is selecting every suite — the safe
# direction.
#
# ACROSS ecosystems each path may take exactly ONE language transition, and this
# asymmetry is load-bearing rather than tidiness. Within a language, "B's text
# contains A's basename" is a real dependency: shell sources shell, Node imports
# Node. Across languages it usually is not — a .ps1 that happens to contain the
# characters "paths.js" is not loading it — so chaining those coincidences
# compounds them. Measured before this rule existed, with the corpus widened to
# four ecosystems and the walk left uncapped: EVERY .js file in the repo selected
# the same 156 of 439 suites, and one selected 376, because the walk crossed
# js -> ps1 -> sh and saturated on the hubs at the far end
# (Assert-CheckResult.ps1, hook-utils.sh). An answer identical for every file in
# a language carries no information about which file changed, which is the tool
# failing at its whole job even though it fails in the "safe" direction.
#
# The budget is one TRANSITION per path, not one hop. A crossed-to file keeps
# walking its OWN language freely; what it may not do is cross a second time.
# The distinction matters and the weaker "one hop then stop" rule was wrong:
# helper.py -> runner.sh -> command.sh -> command.test.sh is a real chain whose
# second edge is shell-to-shell, and stopping dead at runner.sh dropped
# command.test.sh — an under-selection, the direction this file calls unsafe. It
# is the repeated re-crossing that saturates, not depth within one language.
#
# This costs nothing that was ever load-bearing: before the corpus was widened
# the reverse lookup was `-- '*.sh'`, so cross-language edges did not exist at
# all and no shell-to-shell chain is shortened by any of this.
#
# KNOWN LIMIT, in the safe direction: R3/R4 look the basename up with
# `git grep -o -F`, which is an unanchored SUBSTRING search — not a token match
# and not a path match. So ANY basename that is a suffix-substring of another
# path in the corpus matches every mention of that other path. `utils.sh` is a
# substring of `hook-utils.sh`, so a new plugins/guardrails/hooks/utils.sh with
# no real coverage at all selects 64 suites and exits 0 (measured) instead of
# failing unmapped. Naming a file "distinctively" is NOT a defense: whether the
# collision happens is decided by every OTHER path already in the repo, not by
# how distinctive the new name reads on its own. Narrowing this needs real
# shell/path parsing rather than a substring match, which is not worth the
# fail-open risk the narrowing itself would carry. When a new file's basename
# is a substring of an existing path, do not trust a non-empty selection to
# mean the file is covered — check that the selected suites actually name it.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

NO_SUITE_LIST="${AFFECTED_TESTS_NO_SUITE:-scripts/affected-tests-no-suite.txt}"

# Basenames that name a structural role rather than one artifact. R3/R4 ignore
# them; see the note above.
STRUCTURAL_BASENAMES="README.md SKILL.md AGENTS.md CLAUDE.md CHANGELOG.md
plugin.json marketplace.json settings.json hooks.json package.json
package-lock.json index.md LICENSE"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

base_ref=""
do_run=0
allow_unmapped=0
explain=0
print_fanout=""
declare -a explicit_paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --run)
    do_run=1
    shift
    ;;
  --allow-unmapped)
    allow_unmapped=1
    shift
    ;;
  --explain)
    explain=1
    shift
    ;;
  --base)
    # Checked explicitly rather than with `${2:?...}`, which exits 1. Exit 1 is
    # already spoken for twice here — an unmapped changed file, and a failing
    # suite under --run — and the header documents usage errors as 2. A caller
    # that branches on the code cannot tell a typo'd flag from a real finding.
    if [[ $# -lt 2 || -z "$2" ]]; then
      echo "error: --base needs a ref." >&2
      exit 2
    fi
    base_ref="$2"
    shift 2
    ;;
  --base=*)
    base_ref="${1#--base=}"
    shift
    ;;
  --print-fanout)
    # Same as --base above: usage errors exit 2, not 1.
    if [[ $# -lt 2 || -z "$2" ]]; then
      echo "error: --print-fanout needs a path." >&2
      exit 2
    fi
    print_fanout="$2"
    shift 2
    ;;
  --)
    shift
    while [[ $# -gt 0 ]]; do
      explicit_paths+=("$1")
      shift
    done
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    explicit_paths+=("$1")
    shift
    ;;
  esac
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/affected-tests.XXXXXX")" || exit 2
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# Sync-manifest derivation (R5/R6)
# ---------------------------------------------------------------------------

# manifest_src <sync-script> -> the `src=` value, or empty.
manifest_src() {
  awk '/^src=/ {
    v = $0
    sub(/^src=/, "", v)
    gsub(/["\047]/, "", v)
    sub(/[[:space:]]*#.*$/, "", v)
    print v
    exit
  }' "$1"
}

# manifest_copy_patterns <sync-script> -> one raw `copies=(...)` entry per line.
manifest_copy_patterns() {
  awk '
    /^copies=\(/ {
      inarr = 1
      line = $0
      sub(/^copies=\(/, "", line)
    }
    !inarr { next }
    inarr && line == "" && $0 !~ /^copies=\(/ { line = $0 }
    {
      sub(/#.*$/, "", line)
      closed = (line ~ /\)/)
      if (closed) sub(/\).*$/, "", line)
      gsub(/["\047]/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") print line
      if (closed) exit
      line = ""
    }
  ' "$1"
}

# manifest_declares_copies <sync-script> -> 0 if a `copies=(` line EXISTS.
# Deliberately separate from manifest_copy_patterns: whether the declaration is
# PRESENT and whether it YIELDED anything are different questions, and conflating
# them is what let a malformed `copies=()` with no `src=` look like a helper.
manifest_declares_copies() {
  grep -q '^copies=(' "$1"
}

# SYNC_SRC_COPIES maps a sync source path to its newline-separated copy paths.
declare -A SYNC_SRC_COPIES=()
declare -A SYNC_SCRIPT_SRC=()

build_sync_map() {
  local script src pattern match
  local -a patterns=()
  local -a expanded=()
  for script in scripts/sync-*.sh; do
    [[ -f "$script" ]] || continue
    case "$script" in
    *.test.sh) continue ;;
    *) ;;
    esac
    src="$(manifest_src "$script")"
    mapfile -t patterns < <(manifest_copy_patterns "$script")
    # A script matching scripts/sync-*.sh that declares NEITHER key is not a
    # copy manifest — it is a helper that happens to share the prefix. Skip it.
    # Hard-exiting on it would be a repo-wide outage: this suite runs in the
    # plugin-gate lane, so the first future `scripts/sync-something.sh` that is
    # not a manifest would turn a REQUIRED check red for every PR, including
    # ones that never touch this tool. The narrow fail-open that buys, stated
    # plainly: a REAL manifest that renamed BOTH keys at once skips silently,
    # and the zero-manifests guard below only catches the case where every
    # manifest went dark at the same time. Half a manifest is still fatal.
    #
    # The test is on the DECLARATION, not on what it yielded. Asking
    # `${#patterns[@]} -eq 0` instead would read a malformed `copies=()` with no
    # `src=` as a helper and skip it silently — a half-manifest escaping the
    # loud failure this branch exists to preserve, and one the zero-manifests
    # guard below cannot catch while any other manifest still parses.
    if [[ -z "$src" ]] && ! manifest_declares_copies "$script"; then
      continue
    fi
    if [[ -z "$src" ]]; then
      echo "error: $script declares copies=(...) but no src= — the shared-lib derivation cannot read it." >&2
      echo "       Teach scripts/affected-tests.sh the new manifest shape; do not hardcode a copy list." >&2
      exit 2
    fi
    expanded=()
    for pattern in ${patterns[@]+"${patterns[@]}"}; do
      # shellcheck disable=SC2086 # a manifest entry may be a glob; splitting is
      # the expansion, and no path in this repo contains whitespace.
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
    SYNC_SCRIPT_SRC["$script"]="$src"
    printf -v SYNC_SRC_COPIES["$src"] '%s\n' "${expanded[@]}"
  done
  if [[ ${#SYNC_SCRIPT_SRC[@]} -eq 0 ]]; then
    echo "error: no scripts/sync-*.sh manifests found — shared-lib fan-out would be silently empty." >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

declare -A SUITES=()   # suite path -> reason
declare -a UNMAPPED=() # changed paths that mapped to nothing

is_structural() {
  local b="$1" s
  for s in $STRUCTURAL_BASENAMES; do
    [[ "$b" == "$s" ]] && return 0
  done
  return 1
}

# SEED_HITS counts the suites the CURRENT seed reached, whether or not an
# earlier seed had already selected them. Counting only NEWLY added suites was
# wrong and wrong in the dangerous direction: the second of two changed files
# that share a suite looked like it mapped to nothing and was reported unmapped.
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

# is_suite_path <path> -> 0 when the path IS a test suite, in any ecosystem this
# repo actually carries. The conventions are READ from the corpus, not invented:
# shell and Node co-locate <stem>.test.<ext>, Pester suffixes <Stem>.Tests.ps1,
# and Python PREFIXES test_<stem>.py — which is why the Python arm has to test
# the basename rather than the whole path.
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

# lang_family <path> -> the ecosystem a path belongs to, for the one-hop rule
# above. Anything unrecognized gets its own bucket rather than a shared "other":
# two unrelated extensions must not read as the same language and license a walk
# between them.
lang_family() {
  case "$1" in
  *.sh | *.bash) printf 'sh' ;;
  *.js | *.mjs | *.cjs) printf 'node' ;;
  *.py) printf 'py' ;;
  *.ps1 | *.psm1) printf 'ps' ;;
  *) printf 'ext:%s' "${1##*.}" ;;
  esac
}

# colocated_suites <path> -> every sibling suite covering it, one per line.
# PLURAL on purpose: one source file can carry suites in two ecosystems at once
# — a .py with both a co-located test_<stem>.py and a wrapping <stem>.test.sh
# that drives it — and returning only the first is an under-selection, the one
# direction this tool treats as unsafe.
colocated_suites() {
  local p="$1" stem dir base candidate
  if is_suite_path "$p"; then
    printf '%s\n' "$p"
    return 0
  fi
  # An extensionless path keeps its whole name as the stem, which is what
  # ${p%.*} already yields when there is no dot to strip.
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
  )
  # The hyphen fold is a SECOND candidate only when there is a hyphen to fold;
  # otherwise it is character-for-character the previous entry and would emit
  # the same path twice.
  [[ "$base" == *-* ]] && candidates+=("$dir/test_${base//-/_}.py")
  for candidate in ${candidates[@]+"${candidates[@]}"}; do
    [[ -f "$candidate" ]] && printf '%s\n' "$candidate"
  done
  return 0
}

# select_for <changed-path> -> populate SUITES, and set SEED_HITS to the number
# of suites THIS seed reached. The count comes back through a global rather than
# stdout on purpose: a command substitution would run the whole walk in a
# SUBSHELL and every SUITES mutation would be discarded with it.
select_for() {
  local seed="$1"
  local -a frontier=()
  local -a next=()
  local p b sib copy line matched_path matched_name grep_rc
  local origin_family matched_family hop_state
  # PATTERN_ORIGIN maps a batched basename back to the ecosystem of the file that
  # contributed it, and PATTERN_CROSSED records whether that file had already
  # spent its one language transition. When two files in DIFFERENT families
  # contribute the same basename, the origin collapses to '*' and the pattern is
  # treated as same-family against anything — the over-selecting direction, which
  # is the safe one.
  local -A PATTERN_ORIGIN=()
  local -A PATTERN_CROSSED=()
  local -A CROSSED=()
  # The visited set is PER SEED, not shared across seeds. Sharing it made a
  # changed file that an earlier seed had already walked past look unvisited-
  # and-unmapped, which is the fail-open direction: the file would be reported
  # as covered because someone else's walk touched it, or as unmapped because
  # its own walk was short-circuited. Re-walking costs one batched grep.
  local -A VISITED=()
  SEED_HITS=0

  frontier=("$seed")
  # R5: a sync source seeds every copy the manifest declares.
  if [[ -n "${SYNC_SRC_COPIES[$seed]:-}" ]]; then
    while IFS= read -r copy; do
      [[ -n "$copy" ]] && frontier+=("$copy")
    done <<<"${SYNC_SRC_COPIES[$seed]}"
  fi
  # R6: a sync script pulls in whatever its source pulls in.
  if [[ -n "${SYNC_SCRIPT_SRC[$seed]:-}" ]]; then
    frontier+=("${SYNC_SCRIPT_SRC[$seed]}")
    while IFS= read -r copy; do
      [[ -n "$copy" ]] && frontier+=("$copy")
    done <<<"${SYNC_SRC_COPIES[${SYNC_SCRIPT_SRC[$seed]}]:-}"
  fi

  while [[ ${#frontier[@]} -gt 0 ]]; do
    : >"$WORK_DIR/patterns"
    next=()
    for p in "${frontier[@]}"; do
      [[ -n "${VISITED[$p]:-}" ]] && continue
      VISITED["$p"]=1
      # R1/R2
      while IFS= read -r sib; do
        [[ -n "$sib" ]] || continue
        if [[ "$sib" == "$p" ]]; then
          add_suite "$sib" "changed suite" || true
        else
          add_suite "$sib" "co-located with $p" || true
        fi
      done < <(colocated_suites "$p")
      b="${p##*/}"
      is_structural "$b" && continue
      origin_family="$(lang_family "$p")"
      if [[ -z "${PATTERN_ORIGIN[$b]:-}" ]]; then
        PATTERN_ORIGIN["$b"]="$origin_family"
        PATTERN_CROSSED["$b"]="${CROSSED[$p]:-0}"
      else
        [[ "${PATTERN_ORIGIN[$b]}" == "$origin_family" ]] || PATTERN_ORIGIN["$b"]='*'
        # Any contributor that has NOT yet crossed wins: the walk keeps its
        # budget. Over-selection is the safe direction, so a tie resolves toward
        # more walking.
        [[ "${CROSSED[$p]:-0}" == "0" ]] && PATTERN_CROSSED["$b"]=0
      fi
      printf '%s\n' "$b" >>"$WORK_DIR/patterns"
    done

    [[ -s "$WORK_DIR/patterns" ]] || break

    # R3/R4: one batched reverse lookup per level. The hits go through a FILE,
    # not a process substitution, so this lookup can FAIL LOUD like every other
    # step here. `done < <(git grep ... 2>/dev/null || true)` could not: after
    # the loop `$?` holds the LOOP's status, git's stderr was discarded, and
    # `|| true` erased the code, so a git ERROR (exit >= 2 — a bad flag, an
    # unreadable pattern file, a corrupt index) was indistinguishable from NO
    # MATCH (exit 1). Both produced an empty read and the walk simply found no
    # dependents. That is the fail-open this tool exists to refuse, and it
    # lands in the UNDER-selection direction the DIRECTION note above calls
    # unsafe: a broken lookup reported a narrow selection, or "no suites
    # selected", at exit 0. Same reasoning as changed_from_diff below.
    grep_rc=0
    # Every extension lang_family() names must appear here. If it classifies a
    # path into a family but nothing ever greps that path's content, the file is
    # silently under-covered while LOOKING supported — fail-open, and the reason
    # .bash and .cjs are in this list despite the repo carrying none today.
    git grep --untracked -o -F -f "$WORK_DIR/patterns" \
      -- '*.sh' '*.bash' '*.js' '*.mjs' '*.cjs' '*.py' '*.ps1' '*.psm1' \
      >"$WORK_DIR/hits" || grep_rc=$?
    # Exit 1 is "no match" and is completely ordinary — most seeds reach a level
    # with no further dependents. Only above 1 is git itself failing.
    if [[ "$grep_rc" -gt 1 ]]; then
      echo "error: 'git grep' failed (exit $grep_rc) resolving dependents of the current level." >&2
      echo "       Refusing to continue: an unreadable reverse lookup silently UNDER-selects, and" >&2
      echo "       under-selection is reported as success by everything downstream." >&2
      exit 2
    fi
    while IFS= read -r line; do
      matched_path="${line%:*}"
      matched_name="${line##*:}"
      [[ -n "$matched_path" ]] || continue
      if is_suite_path "$matched_path"; then
        # A suite is taken whatever language it is written in: a .test.sh that
        # drives a .py helper is exactly the cross-language coverage this must
        # keep finding.
        add_suite "$matched_path" "references $matched_name" || true
        continue
      fi
      matched_family="$(lang_family "$matched_path")"
      origin_family="${PATTERN_ORIGIN[$matched_name]:-*}"
      if [[ "$origin_family" == '*' || "$matched_family" == "$origin_family" ]]; then
        # Same-family edge: a real dependency, and it spends no budget.
        hop_state="${PATTERN_CROSSED[$matched_name]:-0}"
      elif [[ "${PATTERN_CROSSED[$matched_name]:-0}" == "1" ]]; then
        # This would be a SECOND language transition for the chain reaching here.
        continue
      else
        hop_state=1
      fi
      [[ -n "${VISITED[$matched_path]:-}" ]] && continue
      # AGGREGATE, never assign. One path can be hit several times in a single
      # round by different patterns — a shell wrapper naming both a shell helper
      # and a JS file — and those hits can disagree about whether the chain
      # reaching it has already crossed. A plain assignment let whichever hit
      # `git grep` happened to emit last decide, so an unrelated cross-family
      # mention could spend a path's budget and cut its own same-family walk
      # short: order-dependent UNDER-selection, the direction this file calls
      # unsafe. The path keeps the most permissive state any contributor gives
      # it, matching how PATTERN_CROSSED already resolves its own ties.
      if [[ "${CROSSED[$matched_path]:-1}" != "0" ]]; then
        CROSSED["$matched_path"]="$hop_state"
      fi
      next+=("$matched_path")
    done <"$WORK_DIR/hits"

    frontier=(${next[@]+"${next[@]}"})
  done
}

# ---------------------------------------------------------------------------
# No-suite classification
# ---------------------------------------------------------------------------

declare -a NO_SUITE_PATTERNS=()
load_no_suite_patterns() {
  local line
  if [[ ! -f "$NO_SUITE_LIST" ]]; then
    echo "error: missing $NO_SUITE_LIST — the no-suite classification cannot be applied," >&2
    echo "       and without it every doc and manifest change would report as unmapped." >&2
    exit 2
  fi
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && NO_SUITE_PATTERNS+=("$line")
  done <"$NO_SUITE_LIST"
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

resolve_base() {
  local c
  if [[ -n "$base_ref" ]]; then
    printf '%s' "$base_ref"
    return 0
  fi
  for c in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$c^{commit}" >/dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

changed_from_diff() {
  local base mb
  if ! base="$(resolve_base)"; then
    echo "error: no diff base resolved (tried --base, origin/main, origin/master, main, master)." >&2
    echo "       Pass --base <ref>, or give explicit paths." >&2
    exit 2
  fi
  if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
    echo "error: base ref '$base' does not resolve to a commit." >&2
    exit 2
  fi
  # Compare the WORKING TREE against the merge base: a local developer wants the
  # suites covering the work in front of them, including uncommitted edits, and
  # not the suites for whatever else landed on the base branch meanwhile.
  mb="$(git merge-base "$base" HEAD 2>/dev/null)" || mb="$base"
  # Every failure here is fatal, never an empty list. An empty change set is
  # indistinguishable from "the diff blew up" downstream, and downstream reports
  # it as "nothing to select, exit 0" — the fail-open this whole tool exists to
  # refuse. This function must therefore run in the CURRENT shell (see the call
  # site): from inside a process substitution these exits would kill only the
  # subshell and `mapfile` would happily succeed with nothing.
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
  if [[ -z "${SYNC_SRC_COPIES[$print_fanout]:-}" ]]; then
    echo "error: $print_fanout is not the src= of any scripts/sync-*.sh manifest." >&2
    exit 2
  fi
  printf '%s' "${SYNC_SRC_COPIES[$print_fanout]}"
  exit 0
fi

declare -a changed=()
if [[ ${#explicit_paths[@]} -gt 0 ]]; then
  for p in "${explicit_paths[@]}"; do
    p="${p#./}"
    # Every rule is repo-relative, and so is every sync-manifest key. An
    # absolute path that stayed absolute would miss those keys and then fall
    # through to a broad no-suite pattern — reporting success with no suites,
    # which is the fail-open direction. Normalize what can be normalized and
    # refuse the rest out loud.
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
  # The sort is checked for the same reason the diff above is: reading it from a
  # process substitution would let a failing `sort` yield an EMPTY change set at
  # exit 0, which the very next block reports as "nothing to select".
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

declare -a NO_SUITE_FILES=()
for f in "${changed[@]}"; do
  [[ -n "$f" ]] || continue
  select_for "$f"
  if [[ "$SEED_HITS" -eq 0 ]]; then
    if is_no_suite "$f"; then
      NO_SUITE_FILES+=("$f")
    else
      UNMAPPED+=("$f")
    fi
  fi
done

# `${!SUITES[@]}` cannot carry a `+` default-guard: bash parses `${!NAME...}` as
# an indirect reference and rejects the expanded key list as a variable name.
declare -a selected=()
if [[ ${#SUITES[@]} -gt 0 ]]; then
  # Checked, and read from a file, for the third time and the same reason: a
  # failing `sort` here would empty a NON-EMPTY selection, and the block below
  # would then print "every changed file is a recorded no-suite class" — a
  # statement that is affirmatively false — and exit 0.
  if ! printf '%s\n' "${!SUITES[@]}" | sort -u >"$WORK_DIR/selected"; then
    echo "error: sorting the selected-suite list failed; refusing to report an empty selection" >&2
    echo "       when ${#SUITES[@]} suite(s) were selected." >&2
    exit 2
  fi
  mapfile -t selected <"$WORK_DIR/selected"
fi

if [[ ${#NO_SUITE_FILES[@]} -gt 0 && "$explain" -eq 1 ]]; then
  for f in "${NO_SUITE_FILES[@]}"; do
    echo "no-suite: $f (recorded in $NO_SUITE_LIST; a non-shell CI lane covers it)" >&2
  done
fi

if [[ ${#UNMAPPED[@]} -gt 0 ]]; then
  echo "UNMAPPED: ${#UNMAPPED[@]} changed file(s) map to no test suite:" >&2
  for f in "${UNMAPPED[@]}"; do
    echo "  - $f" >&2
  done
  echo "This is NOT 'nothing to run' — it is 'this tool does not know what covers these'." >&2
  echo "Fix one of: add a co-located <stem>.test.sh; make a suite name the file; or record the" >&2
  echo "path class in $NO_SUITE_LIST with the CI lane that does cover it." >&2
  if [[ "$allow_unmapped" -eq 0 ]]; then
    echo "Re-run with --allow-unmapped to proceed anyway." >&2
    exit 1
  fi
  echo "Proceeding under --allow-unmapped." >&2
fi

if [[ ${#selected[@]} -eq 0 ]]; then
  echo "No suites selected (every changed file is a recorded no-suite class)." >&2
  exit 0
fi

if [[ "$explain" -eq 1 ]]; then
  for s in "${selected[@]}"; do
    echo "select: $s  (${SUITES[$s]})" >&2
  done
fi

if [[ "$do_run" -eq 0 ]]; then
  printf '%s\n' "${selected[@]}"
  exit 0
fi

# Strictly SEQUENTIAL. Two reasons, both measured rather than assumed: running
# these suites in parallel was measured sublinear (they are spawn-bound and the
# box saturates), and several guardrails suites assert wall-clock ceilings that
# fail spuriously under concurrency. Selection, not parallelism, is the lever.
# Only *.test.sh is executable HERE. The other three ecosystems are run by their
# own lanes, with lane-specific invocations this script cannot derive from a
# suite path: `python -m unittest` against a named module, `npm test`, a bare
# `node --test`, vitest, Pester. Guessing one is strictly worse than declining
# to: the wrong runner either errors in a way that reads as the SUITE failing,
# or exits 0 having run nothing, which is a PASS the change never earned. So
# they are named and NOT run, and the exit code says so rather than reporting
# success over suites that never executed.
declare -a runnable=() delegated=()
for s in "${selected[@]}"; do
  case "$s" in
  *.test.sh) runnable+=("$s") ;;
  *) delegated+=("$s") ;;
  esac
done

failed=0
if [[ ${#runnable[@]} -gt 0 ]]; then
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
echo "All ${#runnable[@]} selected suites passed or were skipped."
