#!/usr/bin/env bash
# Shell-portability-lint gate (#1491): flags GNU-only shell constructs in
# changed **/*.sh files and in skill markdown under plugins/*/skills/ (#2704)
# — a class no existing gate covers. Skill markdown is not documentation about
# code: for a skill, the markdown IS the executable surface an agent reads and
# runs, so a GNU-only construct there fails on macOS exactly as it would in a
# .sh file. `shellcheck` lints shell syntax/style; scripts/check-skill-portability.sh
# (#531) matches skill-coupling tokens (stack/forge/branch/tracker defaults)
# against changed *skill* files only. Neither has GNU-vs-BSD regex/flag
# vocabulary, and no runner in this repo's CI uses BSD userland (a Windows
# runner's Git Bash still ships GNU grep/sed, so it would not help either) —
# the exposure is macOS system grep/sed/date/stat/mktemp/sort, unreachable
# from any lane here.
#
#   scripts/check-shell-portability.sh <base-ref>   gate .sh + skill .md a PR changed
#   scripts/check-shell-portability.sh --all         audit every tracked .sh + skill .md
#   scripts/check-shell-portability.sh --paths F...   scan exactly these files
#
# The scanner engine is scripts/lib/shell-portability-scan.awk, run with
# `awk -f` over two data operands: the active token list and the file. This
# file owns mode dispatch, scannability, the skill-md baseline, and reporting.
#
# COST of `--all`, and what stopped being true about it. Per-file time used to
# grow superlinearly, so a handful of files dominated the whole run while the
# great majority cost almost nothing: on
# 2026-08-20 the single worst file took ~123s where its own first 1200 lines
# took ~3s, and the full sweep took ~10 minutes. That was structural rather
# than environmental, and #3481 removed the structure. Every change below was
# made in place with the findings held byte-identical. The one that dominates
# is that the quote-aware walk now RESUMES per physical line of a joined record
# instead of re-walking the whole accumulation.
#
# An earlier revision of this header credited three changes — that walk, a
# chunked buffer for the two derived views, and matching the stat fallback
# ladder inside the window a ladder can occupy — and that list is wrong about
# which of the remaining ones carry weight. Measured on 2026-08-29 by reverting
# ONE change at a time and re-scanning this file, each ablation confirmed
# output-identical first: the doubling `blanks()` pad is worth 2.30x, the
# split-based `after_last_boundary()` 1.69x, the chunked buffer 0.99x, and the
# cheap `index()`/`!~` pre-filters in is_negated() and status_swallowed()
# nothing measurable at all (0.96x, inside the run-to-run noise). The two the
# old list omitted are the two that pay; the buffer and the pre-filters are
# kept because they cost nothing, not because they bought anything here.
#
# What made a file expensive was never its line count, which is why the shape
# was so easy to misread: it was the length of its longest LOGICAL record. A
# file of ordinary one-line commands scanned linearly before and still does
# (25,600 such lines, ~1.7s then, ~1.9s now). A file carrying one long
# quote-joined record paid a quadratic price for it. Cost is linear in file
# length now ONLY while the longest logical record stays bounded: a file that
# is one enormous record is still superlinear in that record's length, just
# with a far smaller constant. The residue tracks record LENGTH, not how many
# hits the record carries. Measured on 2026-08-29 against a synthetic file
# that is one quote-joined record with no hits in it
# at all: 1,600 lines 0.11s, 6,400 lines 0.35s, 25,600 lines 6.58s. Holding the
# record at 6,400 lines and varying hit density instead moved nothing outside
# the noise: 0.35s with no hits, 0.38s with a hit every eighth line, 0.34s with
# a hit on every line.
#
# As dated observations rather than standing claims -- the figures move with
# the corpus and the machine, the shape does not -- both versions measured on
# 2026-08-29 on one machine over one tree, before and after: a file whose body
# is a single ~1,580-line quote-joined record, ~70s before and ~1.8s after; a
# 2,900-line script ~173s before and ~0.4s after; the whole `--all` sweep of
# 1,537 files ~1,019s before and ~35s after; and this gate's own suite, whose
# fixtures re-scan this file, ~471s before and ~15s after.
#
# CI still runs the changed-file mode rather than `--all` (see ci.yml's
# `shell-portability-lint`), and not because of what a sweep costs: a per-PR
# fleet sweep is runner time spent re-proving files the PR did not touch.
#
# `--all` now finishes well inside a 600s command timeout, so an audit no
# longer has to be run detached. What follows is for a run that DOES outlive
# its timeout, and it is kept because misreading a long run's outcome has cost
# real time more than once:
#
#   - A timeout is not flakiness. Re-running an unchanged command that timed
#     out is the predicted outcome, not new information; four attempts were
#     spent on that before it was understood, each recorded as an environment
#     problem.
#   - Do NOT wait on it with `pgrep -f 'check-shell-portability'`. That pattern
#     appears in the waiting shell's OWN command line, so the waiter matches
#     itself and the condition never clears. Wait on the pid instead.
#   - But waiting is not checking, and a pid wait alone is fail-open. A
#     `while kill -0 "$pid" 2>/dev/null; do sleep 15; done` loop reports only
#     WHEN the run ended, never how: the loop's own status is the last `sleep`'s,
#     so it is 0 whether the audit exited 0, 1 (violation) or 2 (usage error).
#     Measured: a child exiting 3 leaves that loop reporting 0. Reading it as
#     "clean" is exactly the fail-open the next paragraph warns about.
#       - If the run IS a child of your shell, `wait "$pid"` yields its real
#         status (measured: 3 for that same child). Use it, and check it.
#       - If it is NOT a child -- started in an earlier shell, or via `setsid`
#         -- `wait` cannot help: it fails with "pid N is not a child of this
#         shell" and returns 127, which is indistinguishable from a real failure
#         if taken at face value. The status is then simply unavailable, so the
#         outcome must be read from the run's own output, and the absence of a
#         success line must be treated as unknown rather than as pass.
#
# Relatedly, if you sweep files individually to find slow ones, key the loop on
# every non-zero status and not only on the timeout status: a loop that reports
# just `rc == 124` passes silently over any file that exits 1, so its silence
# looks like a clean audit when it is really an unasked question.
#
# WHAT is detected is data, not logic: the construct list lives in
# scripts/shell-portability-tokens.txt (override with
# SHELL_PORTABILITY_TOKENS), one ERE pattern per active line, so a reviewer
# re-catch is a one-line data edit. HOW a legitimate hit is excused is this
# script's job.
#
# A token line beginning with `!` names a class this script implements in CODE
# rather than as an ERE, and ACTIVATION stays data even there: the class runs
# only while its `!name` line is active in the token list, so a class-scoped
# unit fixture enables exactly one class the same way `one_token_list` does for
# an ERE. An unrecognized `!name` exits 2 rather than being ignored — a typo
# that silently disabled a class is the fail-open this gate is tuned against.
# Today there is one such class, and it is script-implemented for a reason the
# ERE layer cannot work around:
#
#   !subst-replacement-ampersand — an UNQUOTED `&` in the REPLACEMENT half of a
#   `${var/pat/repl}` / `${var//pat/repl}` expansion. Since bash 5.2 that `&`
#   expands to the text the pattern just matched (the `sed` rule), under the
#   `patsub_replacement` shell option which is ON by default; before 5.2 the
#   same character was an ordinary literal. GNU Bash Reference Manual, Shell
#   Parameter Expansion: "Any unquoted instances of '&' in string are replaced
#   with the matching portion of pattern", and "Backslash escapes '&' in
#   string; the backslash is removed in order to permit a literal '&' in the
#   replacement string"
#   <https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html>.
#   Introduced in bash-5.2 ("New shell option: patsub_replacement", bash NEWS
#   <https://tiswww.case.edu/php/chet/bash/NEWS>); verified locally on bash
#   5.3.15, where `shopt -u patsub_replacement` restores the pre-5.2 literal.
#   This lands on the gate's EXISTING uncovered-platform axis rather than a new
#   one: macOS — the one platform no runner here covers — ships bash 3.2, while
#   every runner in this repo ships 5.2 or later, so the same line silently
#   means two different things on the two platforms. It shipped a real defect
#   in this repo (#2008): a sentinel restored to itself became a no-op and
#   produced a live false positive in a guardrails hook, on bash >=5.2 only.
#
#   It cannot be an ERE token. Matching runs on the `qline`/`cline` views, and
#   `neutralize()` replaces every SEPS character — `&` among them — inside a
#   masked run with a filler; a `${…}` body is masked in its entirety, which is
#   exactly right for every other class (a `;` in an expansion body is data,
#   not an operator) and leaves this one nothing to match on. The class is
#   instead decided by subst_amp_hit(), which reads the ORIGINAL record text
#   inside the `${…}` extents mask_quotes() already tracks, so the one
#   authority on quote/frame structure stays the one authority.
#
# Changed-FILE scoping (not a whole-repo scan on every push) mirrors
# check-skill-portability.sh exactly: a PR is responsible only for the files it
# touches, so enabling a token class never red-lines main — main's push event
# runs only the self-test, and pre-existing uses of a newly active construct
# wait for their owning file's next edit (or a dedicated migration) rather than
# failing every unrelated PR.
#
# A token hit fails UNLESS one of three reviewer-visible escapes applies:
#   1. an auto-recognized same-line BSD-counterpart guard (is_guarded()) — a
#      portable form already attempted on the same line, e.g.
#      `realpath ... || readlink -f ...`;
#   2. a per-site recorded exemption `portability-ok: <reason>` on the hit line
#      or in the contiguous comment block directly above it;
#   3. a whole-file `portability-scope: <reason>` declaration — a dedicated
#      `#`-comment line whose content (after the `#` and optional whitespace)
#      STARTS with the literal token, e.g. `# portability-scope: <reason>` —
#      not merely a line that mentions the string somewhere (a doc-block
#      sentence explaining this very mechanism, or a string literal), which
#      would wrongly exempt a whole file for a reason it never actually
#      declared. For a file that IS this gate's own fixture/test corpus and
#      so necessarily contains the literal constructs it detects as test
#      data (this script's own check-shell-portability.test.sh uses it), not
#      for excusing a real shipped script's real coupling.
#
# Construct matching skips comment-only lines entirely (a `#`-prefixed line,
# after leading whitespace) — this class is live command syntax, not prose;
# several legitimate dual-dialect comments in this corpus name `date -d` /
# `grep -P` only to explain the portable branch below them, and scanning
# comments would flag documentation, not code. A `portability-ok:` marker is
# still recognized on a comment line (same-line trailing note, or the
# contiguous block directly above a hit) — comment-skip is for CONSTRUCT
# matching only, never for annotation detection.
#
# This is a grep-level tripwire, not a semantic proof: it matches per LOGICAL
# line — backslash- and quote-continued physical lines are joined first — so a
# command assembled into a variable before use still evades detection (tracked
# in #1513).
#
# COMMAND POSITION is deliberately not required, and this is the gate's largest
# accepted over-flag. The leading boundary on a token establishes a shell-WORD
# boundary, not command position, so a utility named inside a diagnostic string
# or a heredoc example — `echo "run date -d tomorrow"`, a usage line spelling
# `stat -c FORMAT FILE` — is reported although nothing executes. That is not an
# oversight to be narrowed away: matching against text the shell would treat as
# a string literal is the whole mechanism behind the regex-escape classes,
# where `grep -E "\bword"` lives inside quotes and MUST still be caught.
# Requiring command position for the option-based classes alone would need a
# per-class axis in the token data on top of the word layer (#1551), and every
# partial answer to it trades this false positive for a fail-OPEN — the
# direction this gate is explicitly tuned against. The word layer's first
# consumer, `--` end-of-options (#1562, recorded above dashdash_between() in
# scripts/lib/shell-portability-scan.awk), shows the cost of doing it right:
# suppression fires on nothing weaker than a
# statically unambiguous marker word inside the matched extent.
# `portability-ok: <reason>` is the one-line escape for a diagnostic
# or example that names one of these utilities.
# Guard markers are seeded for the two classes that need one today —
# readlink -f behind a co-located `realpath ... || readlink -f` ladder, and
# stat -c behind a co-located `stat -c ... || stat -f ...` ladder — each
# requiring an actual `||` fallback relationship, not mere co-location; a
# further class enables its own guard here, proven against an `--all` audit
# first — see the token file's STAGED section.
#
# Exit 0 = clean (or nothing in scope); 1 = one or more violations; 2 = usage /
# environment error (fail closed — never a silent skip).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/token-scan.sh
. "$SCRIPT_DIR/lib/token-scan.sh" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

# The scanner engine, as its own awk source file: `awk -f` reports a syntax
# error in it at the line it is on, `awk -f … /dev/null` is a compile check the
# suite runs, and a test can drive the program directly on its two operands
# without this script around it. Absent, the gate fails closed HERE with a
# diagnostic naming the path, rather than once per scanned file as an opaque
# non-zero awk status.
SCAN_AWK="$SCRIPT_DIR/lib/shell-portability-scan.awk"
if [[ ! -f "$SCAN_AWK" ]]; then
  printf 'Error: scanner program not found: %s\n' "$SCAN_AWK" >&2
  exit 2
fi

# require_token_file carries the same awk operand disambiguation the scanned
# file gets below, and for a worse reason: a token path shaped like
# identifier=value (`tokens=custom.txt`) is parsed by awk as a variable
# assignment rather than opened, so the `FNR == NR` loading pass never runs, NO
# patterns are active, and every file reports clean while awk still exits 0 — a
# silent fail-open in the gate itself, invisible to the scanner-fault check.
# See #1513; shared with check-skill-portability.sh, which was missing it
# entirely until #2914.
TOKENS_SRC="${SHELL_PORTABILITY_TOKENS:-scripts/shell-portability-tokens.txt}"
TOKENS="" # assigned through the nameref below; declared so shellcheck sees it
if ! token_scan::require_token_file TOKENS "$TOKENS_SRC"; then
  exit 2
fi

# Active patterns are resolved HERE instead of inside the awk program, so the
# comment/blank rule is the shared one (#3161) rather than a private copy — and
# so this gate stops carrying TWO different rules, since its skill-md baseline
# above already goes through the same library in `inline` mode. `leading` here:
# an entry is an ERE (or a `!class` token) and may legitimately contain a `#`.
#
# `!class` lines count as active, so the empty-set guard below fires only when
# the list yields nothing at all — matching the awk-side `np == 0 && ncls == 0`
# check, which stays as defence in depth.
token_patterns=()
read_list::into token_patterns "$TOKENS_SRC" --comments leading || exit 2
if ((${#token_patterns[@]} == 0)); then
  printf 'Error: token list loaded no active patterns: %s\n' "$TOKENS_SRC" >&2
  exit 2
fi
TOKENS_ACTIVE="$(mktemp)" || exit 2
trap 'rm -f "$TOKENS_ACTIVE"' EXIT
printf '%s\n' "${token_patterns[@]}" >"$TOKENS_ACTIVE"
TOKENS="$(token_scan::awk_operand "$TOKENS_ACTIVE")"

# Pre-existing skill-markdown debt (#2704): widening selection onto every
# SKILL.md / context/*.md / reference/*.md that already carries a token hit
# would be a flag day. scripts/shell-portability-skill-md-baseline.txt
# grandfathers today's measured hits so CI-facing modes gate NEW and CHANGED
# skill markdown first; the baseline shrinks (a stale entry — file missing or
# clean — fails the gate). --paths never consults it: that mode is the audit
# tool that measured the backlog and must keep seeing every hit.
BASELINE="${SHELL_PORTABILITY_MD_BASELINE:-scripts/shell-portability-skill-md-baseline.txt}" # env override is test injection

usage() {
  printf 'usage: check-shell-portability.sh <base-ref> | --all | --paths FILE...\n' >&2
  exit 2
}

# is_scannable <path> — a shell file this gate is responsible for. Vendor/
# upstream-synced copies carry their own drift gate, not this contract.
# Skill markdown under plugins/*/skills/ is in scope (#2704): agents execute
# shell snippets from those files. Plugin reference docs under
# plugins/*/reference/ are in scope for the same reason — a shared engine doc a
# skill body cites carries the same executable snippets, and extracting a block
# out of a skill and into a reference must not silently drop its gate coverage.
# evals/ carries adversarial fixture prompts by design (same exclusion
# check-skill-portability.sh uses). Likewise the
# cross-plugin sync copies registered in
# scripts/cross-plugin-source-registry.txt: a dedicated gate holds each copy
# byte-identical to its in-repo SOURCE, so the source is where this contract
# gates a change — scanning each copy would flag content no copy edit is
# allowed to fix.
is_scannable() {
  local f="$1"
  case "$f" in
  */vendor/* | */evals/*) return 1 ;;
  *.sh) ;;
  plugins/*/skills/*.md) ;;
  plugins/*/reference/*.md) ;;
  *) return 1 ;;
  esac
  local registry="scripts/cross-plugin-source-registry.txt" rel line
  if [[ "$f" == plugins/*/* && -r "$registry" ]]; then
    rel="${f#plugins/}"
    rel="${rel#*/}"
    while IFS= read -r line; do
      case "$line" in '' | \#*) continue ;; *) ;; esac
      [[ "$rel" == "$line" ]] && return 1
    done <"$registry"
  fi
  return 0
}

# Active baseline entries: exact repo-relative paths, full-string equality.
baseline_entries=()
if [[ -f "$BASELINE" ]]; then
  # `inline`: baseline entries are repo-relative paths, never regexes, so a `#`
  # anywhere on the line is a comment. This gate's OTHER list — the token file —
  # takes `leading` instead, because its entries are EREs that may contain a
  # `#`. Those two modes are exactly the divergence #3161 collapsed into one
  # library; this file is the one that carried both shapes.
  read_list::into baseline_entries "$BASELINE" --comments inline || exit 2
fi

baselined() {
  local path="$1" entry
  for entry in "${baseline_entries[@]}"; do
    [[ "$path" == "$entry" ]] && return 0
  done
  return 1
}

files=()
apply_baseline=0
if (($# == 0)); then
  usage
fi

mode="$1"
case "$mode" in
--all)
  shift
  (($# == 0)) || usage
  apply_baseline=1
  while IFS= read -r f; do
    is_scannable "$f" && files+=("$f")
  done < <(
    {
      find . -type f -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.git/*'
      find plugins -type f -path 'plugins/*/skills/*' -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
      find plugins -type f -path 'plugins/*/reference/*' -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
    } | sed 's|^\./||' | sort -u
  )
  ;;
--paths)
  shift
  (($# > 0)) || usage
  # --paths is the audit tool: scan exactly what was asked, no baseline skip.
  files=("$@")
  ;;
-*)
  usage
  ;;
*)
  # Changed-file mode: <base-ref>.
  base="$mode"
  shift
  (($# == 0)) || usage
  apply_baseline=1
  if ! changed_files::verify_base "$base"; then
    printf 'Error: base ref %s is not a valid commit\n' "$base" >&2
    exit 2
  fi
  # The NUL-safe read and the deletion filter live in the shared resolver; a
  # failed diff is fatal there rather than arriving here as an empty scope.
  # Diff plugins/ in addition to *.sh so skill markdown under
  # plugins/*/skills/ reaches is_scannable (#2704); a plugins/*/skills/
  # pathspec alone does not match under git's default (non-pathname) globbing
  # (same rationale as check-skill-portability.sh).
  changed=()
  changed_files::into changed "$base" -- '*.sh' 'plugins/' || exit 2
  for f in ${changed[@]+"${changed[@]}"}; do
    is_scannable "$f" || continue
    [[ -f "$f" ]] || continue # a rename-away/deletion leaves nothing to scan
    files+=("$f")
  done
  ;;
esac

if ((${#files[@]} == 0)); then
  echo "No shell files in scope — nothing to gate."
  exit 0
fi

# scan_file <path> — print `LINE: token -> text` for each unexcused hit.
scan_file() {
  local file="$1"
  # The whole-file `portability-scope:` declaration is recognized INSIDE the awk
  # program rather than by a pre-pass grep here. A grep sees no shell structure,
  # so it honored the declaration wherever the characters appeared — including a
  # heredoc BODY, where the line is generated data rather than a declaration this
  # file is making about itself, and one such line silently exempted the whole
  # file (#1544). awk already tracks heredocs and quoted runs for the scan, so
  # the one place that knows what is code is the one place that decides.
  #
  # awk operand disambiguation: a bare relative operand shaped like
  # identifier=value (e.g. a top-level file literally named FOO=bar.sh) is
  # parsed by awk as a command-line variable assignment, not opened as a
  # file — silently dropping it from the scan. See #1513; the rule now lives in
  # scripts/lib/token-scan.sh, shared with the twin scanner.
  local awk_file
  awk_file="$(token_scan::awk_operand "$file")"
  awk -f "$SCAN_AWK" "$TOKENS" "$awk_file"
}

violations=0
# Whether any reported hit belongs to the bash-version class, so its remediation
# paragraph is printed to the developer who actually hit it and to nobody else.
# Printed unconditionally it followed every `grep -P` and `sed -i` failure with
# advice about an ampersand the developer never wrote.
amp_violation=0
# Baselined skill-md paths that still produced at least one hit this run — used
# by the stale-baseline guard below so a cleaned-up file cannot linger on the
# backlog list.
declare -A baseline_still_hot=()
declare -A files_in_scope=()
for file in "${files[@]}"; do
  files_in_scope["$file"]=1
  if [[ ! -f "$file" ]]; then
    printf 'Error: no such file: %s\n' "$file" >&2
    exit 2
  fi
  # Propagate a scanner fault (e.g. a malformed active ERE token makes awk exit
  # non-zero with no stdout): without this the empty $out reads as "clean" and
  # the file is silently skipped — the exact false negative fail-closed forbids.
  out="$(scan_file "$file")" || {
    printf 'Error: gate scanner failed on %s — failing closed\n' "$file" >&2
    exit 2
  }
  if [[ -n "$out" ]]; then
    # shellcheck disable=SC2310 # baselined only walks a static array
    if ((apply_baseline)) && baselined "$file"; then
      baseline_still_hot["$file"]=1
      continue
    fi
    while IFS= read -r v; do
      echo "PORTABILITY: ${file}:${v}" >&2
      violations=$((violations + 1))
      case "$v" in
      *"!subst-replacement-ampersand"*) amp_violation=1 ;;
      *) ;;
      esac
    done <<<"$out"
  fi
done

# Stale-baseline guard (CI-facing modes only): every entry must name a skill-md
# file that still carries at least one unexcused hit when scanned. A missing
# file or a cleaned-up file must leave the list — same shrink-only contract as
# scripts/orphaned-fixtures-baseline.txt / hook-userconfig-argv-allowlist.txt.
#
# All three stale branches share changed-file scoping: --all re-proves the
# whole list; diff mode only re-proves entries in this run's file set. Missing
# targets are never in that set (diff excludes deletions), so a deleted
# baseline path is caught on the next `--all` rather than red-lining unrelated
# PRs — same blast-radius contract as the cleaned-up / out-of-set branches.
if ((apply_baseline)) && ((${#baseline_entries[@]} > 0)); then
  for entry in "${baseline_entries[@]}"; do
    if [[ "$mode" == "--all" || -n "${files_in_scope[$entry]:-}" ]]; then
      if [[ ! -f "$entry" ]]; then
        echo "STALE BASELINE: $BASELINE: '$entry' names a missing file — remove it" >&2
        violations=$((violations + 1))
        continue
      fi
      if [[ -z "${baseline_still_hot[$entry]:-}" ]]; then
        # Confirm scannable rather than trusting set membership alone: a
        # baseline entry that is_scannable rejected (vendor/evals) must still
        # be shed.
        if is_scannable "$entry"; then
          echo "STALE BASELINE: $BASELINE: '$entry' no longer has unexcused hits — remove it" >&2
        else
          echo "STALE BASELINE: $BASELINE: '$entry' is outside the scannable skill-md set — remove it" >&2
        fi
        violations=$((violations + 1))
      fi
    fi
  done
fi

if ((violations > 0)); then
  {
    echo
    echo "A GNU-only construct in a shell script is silently incompatible with"
    echo "BSD userland (macOS system grep/sed/date/stat/mktemp/sort) — no CI"
    echo "runner in this repo covers that platform, so a regression here ships"
    echo "undetected. Resolve the construct with a POSIX-portable form, or —"
    echo "when the use is legitimate and reviewed — add a"
    echo "'portability-ok: <reason>' comment at the site."
  } >&2
  if ((amp_violation > 0)); then
    {
      echo
      echo "!subst-replacement-ampersand names the one class above that is a bash"
      echo "VERSION divergence rather than a utility one: since bash 5.2 an"
      echo "unquoted '&' in the replacement half of \${var//pat/repl} expands to"
      echo "the text the pattern just matched, so the same line means two things"
      echo "on macOS (bash 3.2) and on this repo's runners (5.2+). Spell a literal"
      echo "ampersand '\\&': the manual states the backslash is removed to permit"
      echo "a literal '&', and the quoted spellings carry their own pre-4.3"
      echo "quote-removal divergence."
    } >&2
  fi
  exit 1
fi
echo "No unexcused GNU-only constructs in ${#files[@]} shell file(s)."
