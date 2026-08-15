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
# consumer, `--` end-of-options (#1562, recorded above dashdash_between()),
# shows the cost of doing it right: suppression fires on nothing weaker than a
# statically unambiguous marker word inside the matched extent.
# `portability-ok: <reason>` is the one-line escape for a diagnostic
# or example that names one of these utilities.
# Guard markers are seeded for the one class that needs one today
# (readlink -f, requiring an actual `||` fallback relationship with a
# co-located realpath attempt — not mere co-location); a further class
# enables its own guard here, proven against an `--all` audit first — see the
# token file's STAGED section.
#
# Exit 0 = clean (or nothing in scope); 1 = one or more violations; 2 = usage /
# environment error (fail closed — never a silent skip).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

TOKENS="${SHELL_PORTABILITY_TOKENS:-scripts/shell-portability-tokens.txt}"
if [[ ! -f "$TOKENS" ]]; then
  printf 'Error: token list not found: %s\n' "$TOKENS" >&2
  exit 2
fi
# Same awk operand disambiguation the scanned file already gets below, and for
# a worse reason: a token path shaped like identifier=value (`tokens=custom.txt`)
# is parsed by awk as a variable assignment rather than opened, so the
# `FNR == NR` loading pass never runs, NO patterns are active, and every file
# reports clean while awk still exits 0 — a silent fail-open in the gate itself,
# invisible to the scanner-fault check. See #1513.
case "$TOKENS" in
./* | /*) ;;
*) TOKENS="./$TOKENS" ;;
esac

# Pre-existing skill-markdown debt (#2704): widening selection onto every
# SKILL.md / context/*.md / reference/*.md that already carries a token hit
# would be a flag day. scripts/shell-portability-skill-md-baseline.txt
# grandfathers today's measured hits so CI-facing modes gate NEW and CHANGED
# skill markdown first; the baseline shrinks (a stale entry — file missing or
# clean — fails the gate). --paths never consults it: that mode is the audit
# tool that measured the backlog and must keep seeing every hit.
BASELINE="${SHELL_PORTABILITY_MD_BASELINE:-scripts/shell-portability-skill-md-baseline.txt}"

usage() {
  printf 'usage: check-shell-portability.sh <base-ref> | --all | --paths FILE...\n' >&2
  exit 2
}

# is_scannable <path> — a shell file this gate is responsible for. Vendor/
# upstream-synced copies carry their own drift gate, not this contract.
# Skill markdown under plugins/*/skills/ is in scope (#2704): agents execute
# shell snippets from those files. evals/ carries adversarial fixture prompts
# by design (same exclusion check-skill-portability.sh uses). Likewise the
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
# SHELL_PORTABILITY_MD_BASELINE overrides the path (test injection).
baseline_entries=()
if [[ -f "$BASELINE" ]]; then
  mapfile -t baseline_entries < <(sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$BASELINE" | grep -v '^$' || true)
fi

# baselined <path> — 0 when the path is on the skill-md backlog list.
baselined() {
  local path="$1" entry
  for entry in "${baseline_entries[@]}"; do
    [[ "$path" == "$entry" ]] && return 0
  done
  return 1
}

# Resolve the file set for the requested mode.
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
  if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
    printf 'Error: base ref %s is not a valid commit\n' "$base" >&2
    exit 2
  fi
  # NUL-delimited (-z) so a pathname Git would C-quote (non-ASCII bytes under
  # the default core.quotePath, or a literal quote/backslash) arrives verbatim
  # — a quoted path would miss the *.sh / skill-md suffix check below and be
  # silently dropped, the exact silent exclusion the contract forbids.
  # Diff plugins/ in addition to *.sh so skill markdown under
  # plugins/*/skills/ reaches is_scannable (#2704); a plugins/*/skills/
  # pathspec alone does not match under git's default (non-pathname) globbing
  # (same rationale as check-skill-portability.sh).
  while IFS= read -r -d '' f; do
    is_scannable "$f" || continue
    [[ -f "$f" ]] || continue # a rename-away/deletion leaves nothing to scan
    files+=("$f")
  done < <(git diff --name-only --diff-filter=d -z "$base" -- '*.sh' 'plugins/' | sort -z -u)
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
  # file — silently dropping it from the scan. Prefixing an unrooted operand
  # with `./` breaks the identifier=value shape (`./` is never a valid awk
  # identifier lead character) so it is unambiguously a filename. See #1513.
  local awk_file="$file"
  case "$awk_file" in
  ./* | /*) ;;
  *) awk_file="./$awk_file" ;;
  esac
  awk '
    # Spelled as octal escapes because this program is itself embedded in a
    # single-quoted shell word, where a literal quote cannot appear.
    BEGIN {
      SQ = "\047"; DQ = "\042"; BS = "\134"; BT = "\140"; NL = "\012"
      # The label a script-implemented class reports under. It is the token
      # line that activates it, verbatim, so a reported hit greps straight back
      # to the data line that turned the class on — the same relationship an
      # ERE hit has with its own token.
      AMPTOK = "!subst-replacement-ampersand"
      # A newline is a separator too, and it reaches a record only through a
      # quote-continued join. Inside a QUOTED run it is ordinary data, so
      # neutralizing it is what lets a token gap span the join: a `stat` whose
      # quoted filename contains a newline is one command whose option the gate
      # could not otherwise reach (#1544). Inside a `$( )` or backquote frame
      # the mask leaves it
      # structural, because there it really does end a command.
      SEPS = ";&|()" NL BT
      # The `stat` COMMAND NAME as an ERE, quote-runs interleaved between its
      # letters. Shell quote removal happens before the utility sees argv, so
      # `st"a"t -c %s` invokes the same GNU stat as `stat -c %s` and admitted
      # the same GNU-only option while reading clean (#1544).
      #
      # One constant, two consumers: the token file spells the name this way,
      # and the fallback guard below ANCHORS its own ladder regex with it so a
      # quote-spliced GNU call can still find its quote-spliced BSD fallback.
      # The guard DISPATCHES on either spelling — a token naming the utility
      # plainly is still a stat token, and a simplified one is what every
      # class-scoped unit fixture uses.
      QRUN = "(\\$?[" SQ DQ "]|" BS BS ")*"
      STATNAME = "s" QRUN "t" QRUN "a" QRUN "t"
      # What may sit between a pipeline position and the command name that
      # position runs: environment assignments (repeatable, either side of a
      # wrapper), an invocation wrapper, or a leading backslash. None changes
      # WHICH command runs, so all are transparent both to the fallback guard
      # after a `||` and to the negation check before a `!`-prefixed call.
      # A transparent prefix WORD: an environment assignment or a redirection.
      # Neither changes which command the position runs — 2.9.1 lets a simple
      # command carry redirections and assignments before its name — so both
      # are transparent to the fallback guard after a `||` and to the negation
      # check before a `!`-prefixed call. Matching only assignments let
      # `! 2>/dev/null stat -c …` read as unnegated (#1544).
      # The redirection operand may be separated from its operator by blanks —
      # 2.7 makes the target a separate word — so `|| 2> /dev/null stat -f …`
      # is one command with a prefix redirection, exactly like the attached
      # spelling. Requiring attachment rejected a genuine dual-dialect ladder.
      ASSIGN = "(([A-Za-z_][A-Za-z0-9_]*=[^;|&[:space:]]*|[0-9]*[<>][<>]?&?[[:space:]]*[^;|&[:space:]]*)[[:space:]]+)*"
      PREFIXES = ASSIGN "((command|env)[[:space:]]+)?" ASSIGN "(\\\\)?[[:space:]]*"
      # Characters a shell word may begin after, for the `#` comment test.
      # `)` is among them because it is a control operator, so `(cmd)# …`
      # comments out the rest of the record; omitting it left a commented-out
      # `|| stat -f` structural and it was accepted as a real guard (#1544).
      # A NEWLINE joins the class once a record can span physical lines: inside
      # a `$( )` or backquote frame a following line may open with a real
      # comment, and leaving it structural would let a commented-out `|| stat
      # -f` on that line excuse a hit on an earlier one — the same fail-open
      # the `)` entry above records, reached through a join.
      WORDSTART = " \t;&|()" NL BT
      # What may sit between a `!` and the command name it negates BEYOND the
      # PREFIXES above: an opener that starts a nested command context. A
      # substitution or subshell is a WORD of the negated pipeline, so the `!`
      # still governs the command inside it — `! x=$(stat -c …) || stat -f …`
      # skips the fallback on BSD exactly as the unnested spelling does.
      NEGOPEN = "(([A-Za-z_][A-Za-z0-9_]*=)?(\\$\\(|" BT "|\\()[[:space:]]*)*"
    }
    function is_annotated(l) { return l ~ /portability-ok:/ }
    function is_comment(l) { return l ~ /^[[:space:]]*#/ }
    # Same-line auto-guard: a portable BSD-side attempt already co-located on
    # the hit line, ACTUALLY WIRED as the fallback (a `||` between the two
    # calls) — not merely mentioned somewhere on the line. Scoped to the two
    # active shapes that need one today:
    #   - readlink -f, guarded by a co-located `realpath ... || readlink -f
    #     ...` fallback ladder (the shape lib/hook-utils.sh already uses).
    #     Requiring the literal `||` between the two (not just both
    #     substrings present) matters: `realpath "$1"; readlink -f "$1"` runs
    #     the GNU-only call unconditionally right after a realpath attempt
    #     with no fallback relationship at all, and must still flag.
    #     The counterpart must also sit at COMMAND POSITION after that `||`,
    #     not merely somewhere to its right. A line whose failure branch only
    #     PRINTS the BSD form names it inside a diagnostic string, so treating
    #     that as a guard would suppress a real GNU-only call behind a
    #     fallback that does not exist (#1544).
    #   - stat -c, guarded by a co-located `stat -c ... || stat -f ...`
    #     fallback ladder (the shape
    #     plugins/repo-hygiene/skills/clean/scripts/remove-path.sh dev_of()
    #     already uses) — same `||`-required rigor as the readlink guard
    #     (#1510).
    # Takes the matched pattern text too, so each guard applies only when its
    # own pattern matched — a line that merely mentions "realpath" or
    # "stat -f" elsewhere must not blanket-excuse a different active
    # pattern hit on the same line. A further class enables its own marker
    # here when it is activated (see the token file STAGED section) — this is
    # deliberately not a generic heuristic, the same posture
    # check-skill-portability.sh takes.
    #
    # sed -i has NO guard. An earlier revision auto-guarded the space-
    # separated empty-suffix idiom ("-i" followed by an empty quoted string
    # as a SEPARATE argument), believing it to be the portable BSD-safe form
    # — that was wrong, verified against a real GNU sed 4.9: that exact
    # invocation exits 2, because GNU consumes the space-separated empty
    # string as the sed SCRIPT argument, leaving the real script and the
    # target file to be opened as filenames. It is BSD-only, not portable, so it
    # correctly stays flagged. The actually dual-compatible spelling is an
    # ATTACHED nonempty suffix (sed -i.bak ... && rm -f the backup after),
    # which this token never matches (attached, no separating whitespace)
    # and so is correctly never flagged.
    #
    # Which characters bound one command, and which `||` a guard may cross,
    # are decided by the segmenter below rather than by the guard regex.
    # ---- Quote-aware command segmentation (#1544) ----
    # Which run of characters is ONE command is decided on a MASKED copy of
    # the line, in which every character inside a quoted run — the quote
    # characters included — is replaced by a filler. A separator that is
    # merely a literal inside a string is therefore never read as a control
    # operator. POSIX Shell Command Language 2.3 Token Recognition rule 4:
    # an unquoted <backslash>, single-quote, or double-quote "shall affect
    # quoting for subsequent characters up to the end of the quoted text";
    # 2.2.2: single-quotes "preserve the literal value of each character
    # within the single-quotes"; 2.2.3: double-quotes preserve it "with the
    # exception of the characters backquote, <dollar-sign>, and <backslash>"
    # — so the mask keeps a backslash escaping its successor in both the
    # unquoted and the double-quoted state, and neither inside single quotes.
    # <https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html>
    #
    # An ERE character class cannot hold that state, which is why the gap
    # alone both over- and under-reached:
    #   - `stat "name;part" -c "%s"` was MISSED — the gap stopped at a `;`
    #     that is a filename character, not an operator;
    #   - `stat -c … ; stat -c … || stat -f …` reported NEITHER call — the
    #     guard was evaluated line-wide, so one guarded ladder anywhere on
    #     the line excused an unconditional GNU-only call before it.
    # Neither is fixable inside the ERE: quote state and per-occurrence guard
    # binding both need memory. The state belongs in this layer.
    #
    # Matching still runs against the ORIGINAL segment text, never the mask:
    # the GNU regex-escape classes (`\b`, `\s`, `\<`, …) legitimately live
    # INSIDE string literals — `grep -E "\bword"` — and must keep matching
    # there. The mask decides structure only.
    # (Both examples are spelled with double quotes because this awk program
    # is embedded in a single-quoted shell word; the single-quoted spellings
    # they stand for behave identically for the point being made.)
    #
    # A command SUBSTITUTION is shell code, not literal text, even inside
    # double quotes — 2.2.3 exempts exactly backquote, dollar-sign and
    # backslash from the literal treatment, which is why `"$(cmd)"` runs cmd.
    # So the mask leaves a `$( )` or backquoted body UNMASKED and structural
    # wherever it opens, and resumes the enclosing state at its close. An
    # earlier revision masked whole double-quoted arguments and lost the
    # nested commands entirely: `printf -- "%s" "$(stat -c "%s" "$f")"`
    # reported clean because the OUTER `--` truncated everything after it,
    # nested invocation included (#1544 review round 2).
    #
    # The state stack is what makes that resumable: `"$(cmd "x")"` re-enters
    # double quotes for the inner argument and must still return to the outer
    # ones at the closing paren.
    #
    # A PARAMETER EXPANSION `${…}` is likewise structural-looking but its body
    # is not shell code: 2.6.2 gives the word after `:-`/`:=`/`%`/`#`/`//` to
    # the expansion, so a `;`/`|`/`&`/`(` in there is data, never a control
    # operator. Only `$(` and a backquote inside it reopen real command text.
    # Without that state `stat ${file:-name;part} -c %s` read the `;` as a
    # command boundary and the GNU-only `-c` after it was never reached
    # (#1544).
    #
    # An INLINE COMMENT is not shell code either. 2.3 rule 10: an unquoted `#`
    # at the START of a word begins a comment that runs to the newline, so
    # nothing after it is structural. Two fail-opens came from treating it as
    # ordinary text (#1544 review round 8):
    #   echo ok # portability-ok: x \   the trailing backslash is comment text,
    #   date -d tomorrow                not a continuation — joining the two
    #                                   carried the annotation onto a
    #                                   standalone GNU-only command;
    #   stat -c %s "$f" # || stat -f    a commented-out fallback satisfied the
    #                                   guard, excusing an unguarded call.
    # The comment body is masked, so its separators are no longer control
    # operators. Construct MATCHING is deliberately untouched — it runs on the
    # original text, so `# see date -d` still reports, the same over-flag
    # direction that the comment-skip in scan_logical — not this mask — is what
    # exempts a comment-ONLY line from.
    #
    # It also RECORDS the extent of every `${…}` parameter expansion it closes,
    # into VS/VE (NV of them). The bash-5.2 `&`-in-replacement class needs the
    # one thing an ERE cannot have and this walk already computes: where an
    # expansion begins and ends, with its own quoting and nesting honored. A
    # second quote tracker written beside this one is the matched-pair shape
    # that has already produced two defects in this corpus — one side widened,
    # the other not — so the class reads these extents instead.
    function mask_quotes(l,   i, c, m, st, top, len) {
      m = ""
      DANGLING_BS = 0
      DANGLING_QUOTE = 0
      NV = 0
      st = "U"
      len = length(l)
      for (i = 1; i <= len; i++) {
        c = substr(l, i, 1)
        top = substr(st, length(st), 1)
        # Single quotes preserve every character (2.2.2) — nothing opens
        # inside them, not even a substitution.
        if (top == "S") {
          m = m "Q"
          if (c == SQ) st = substr(st, 1, length(st) - 1)
          continue
        }
        # An unquoted backslash quotes exactly its successor (2.2.1), so
        # `\"` opens no string. Mask both, never running past the line end.
        # With NOTHING to quote it is escaping the newline — a line
        # continuation, reported through DANGLING_BS so the record loop can
        # join the physical lines into the one command the shell sees.
        if (c == BS) {
          m = m "Q"
          if (i < len) { m = m "Q"; i++ }
          else DANGLING_BS = 1
          continue
        }
        if (c == BT) {
          m = m c
          if (top == "B") st = substr(st, 1, length(st) - 1)
          else st = st "B"
          continue
        }
        # An ARITHMETIC EXPANSION `$(( … ))` is data, not command text, and it
        # must claim the `$((` spelling before the command-substitution branch
        # below can read it as a `$(` plus a stray `(`. Letting that happen
        # left the frame stack unbalanced — the first `)` popped the
        # substitution and the second was consumed as expansion data, so
        # collapse_subs() never closed every frame and blanked the rest of the
        # line: `stat ${x:-$((1 | 2))} -c %s` reported clean (#1544).
        #
        # ARDEPTH tracks parenthesis nesting per frame so an inner `( … )`
        # group (`$(( ((1)) + 2 ))`) cannot close the expansion early; the
        # frame ends only at a `))` reached at depth zero.
        if (c == "$" && substr(l, i + 1, 1) == "(" && substr(l, i + 2, 1) == "(") {
          m = m "QQQ"
          st = st "A"
          ARDEPTH[length(st)] = 0
          i += 2
          continue
        }
        if (c == "$" && substr(l, i + 1, 1) == "(") {
          m = m "Q("
          st = st "P"
          i++
          continue
        }
        if (c == "$" && substr(l, i + 1, 1) == "{") {
          m = m "QQ"
          st = st "V"
          VOPEN[length(st)] = i
          i++
          continue
        }
        # Inside an expansion body every character is data — but a nested
        # `$(`/backquote above still reopens command text, so those branches
        # deliberately sit before this one.
        #
        # A quote inside the body still quotes: the word after `:-` is an
        # ordinary word (2.6.2), so a `}` inside it is data and does NOT end
        # the expansion. Closing at the first `}` regardless let
        # `stat ${f:-"};part"} -c %s` end the expansion early, after which the
        # literal `;` read as a command boundary and hid the `-c` (#1544).
        if (top == "A") {
          m = m "Q"
          if (c == "(") ARDEPTH[length(st)]++
          else if (c == ")") {
            if (ARDEPTH[length(st)] > 0) ARDEPTH[length(st)]--
            else if (substr(l, i + 1, 1) == ")") {
              m = m "Q"
              st = substr(st, 1, length(st) - 1)
              i++
            }
          }
          continue
        }
        if (top == "V") {
          m = m "Q"
          if (c == SQ) st = st "S"
          else if (c == DQ) st = st "D"
          else if (c == "}") {
            # The frame is recorded only where it CLOSES, so an expansion left
            # open at end of record contributes nothing — the record loop joins
            # the next physical line and this walk runs again over the whole.
            NV++
            VS[NV] = VOPEN[length(st)]
            VE[NV] = i
            st = substr(st, 1, length(st) - 1)
          }
          continue
        }
        if (top == "D") {
          m = m "Q"
          if (c == DQ) st = substr(st, 1, length(st) - 1)
          continue
        }
        # Unquoted shell state (U, or inside a `$( )`/backquote body): a `#`
        # opening a word comments out the rest of the record. A `#` mid-word
        # (`foo#bar`, `$#`) is an ordinary character and falls through.
        if (c == "#" && (i == 1 || index(WORDSTART, substr(l, i - 1, 1)) > 0)) {
          while (i <= len) { m = m "Q"; i++ }
          break
        }
        if (c == SQ) { m = m "Q"; st = st "S"; continue }
        if (c == DQ) { m = m "Q"; st = st "D"; continue }
        # A raw SUBSHELL group gets its own frame. Left untracked, its closing
        # paren popped the enclosing `$( )` instead, after which the real close
        # and every separator past it were masked as expansion data — so
        # `x="$( (true); stat -c %s "$f"; true)" || stat -f %z "$f"` read as a
        # guarded ladder although the trailing `true` owns the status (#1544).
        # Same unbalanced-frame failure the arithmetic branch above fixes, one
        # spelling over. A `)` with no frame open stays untouched: it is a
        # `case` pattern terminator, not a close.
        if (c == "(") { m = m c; st = st "G"; continue }
        if (c == ")" && (top == "P" || top == "G")) {
          m = m c
          st = substr(st, 1, length(st) - 1)
          continue
        }
        m = m c
      }
      # Anything still open at end of record — a quote, an expansion, a
      # substitution frame — means the shell has not finished this word, so the
      # next physical line is part of the SAME command. The record loop joins
      # on this exactly as it does on a dangling backslash.
      DANGLING_QUOTE = (length(st) > 1)
      return m
    }
    # ---- Offset-anchored matching (#1544) ----
    # Structure is decided from the MASK, never by re-splitting the line into
    # commands. Three derived views do all the work:
    #
    #   qline  - the line with a separator NEUTRALIZED wherever the mask says
    #            it is inside quotes. The token gaps keep excluding separators
    #            as they always have, so `stat "$f"; tool -c x` is still not a
    #            stat hit, while `stat "name;part" -c "%s"` finally is: that
    #            `;` is a filename character, and only the mask can tell the
    #            difference. Matching runs on qline rather than the mask, so
    #            the GNU regex-escape classes still match inside string
    #            literals - `grep -E "\bword"` is untouched. (Examples here use
    #            double quotes only because this awk program is embedded in a
    #            single-quoted shell word.)
    #
    #   cline  - the same line with every command-substitution and subshell body
    #            collapsed to a non-separator filler. To the command that owns
    #            it a `$(…)` is ONE WORD, so an option after it belongs to that
    #            command: GNU stat and date both accept options after operands
    #            (`stat "$(get_file)" -c %s`), yet the token gaps stopped at the
    #            `(` and never reached the flag (#1544). Collapsing is
    #            length-preserving, so an offset means the same thing in every
    #            view. cline is matched IN ADDITION to qline, never instead of
    #            it — that is what keeps the nested command visible:
    #            `printf -- "%s" "$(stat -c %s "$f")"` has its inner call
    #            collapsed away here and is caught on qline, and a hit on either
    #            view reports the line once.
    #
    #   HIT    - the offset where the construct actually matched. The guard
    #            searches forward from there instead of scanning the whole
    #            line, which is what binds a fallback ladder to the invocation
    #            it guards: in `stat -c … ; stat -c … || stat -f …` the first
    #            call cannot reach the `||`, because SEG stops at the `;`.
    #
    # This deliberately does NOT re-derive command boundaries for every token.
    # An earlier revision did, and changing segmentation globally broke two
    # unrelated classes that depend on the outer command continuing across a
    # substitution (`grep -e "$(printf pattern)" -P file`) or on a process
    # substitution staying attached to its option cluster (`echo -e<(printf x)`).
    # The mask is additive; re-segmentation was not.
    function neutralize(l, m,   i, c, r, len) {
      r = ""
      len = length(l)
      for (i = 1; i <= len; i++) {
        c = substr(l, i, 1)
        # A quoted NEWLINE neutralizes to a SPACE, not to the `Q` filler. `Q` is
        # a word character, so it would weld the text on either side of a join
        # into one word and defeat the very leading boundary the command-word
        # tokens rely on — the hit after a join stopped matching at all. A
        # space is what the shell would never make of it either way, and it
        # leaves the token gaps free to span the join.
        if (substr(m, i, 1) == "Q" && c == NL) r = r " "
        else if (substr(m, i, 1) == "Q" && index(SEPS, c) > 0) r = r "Q"
        else r = r c
      }
      return r
    }
    # The guard is always evaluated on qline, whichever view produced the hit: a
    # ladder whose BSD side sits inside a substitution
    # (`stat -c %s "$f" || x=$(stat -f %z "$f")`) is invisible on cline, and
    # reading the guard there would newly flag a line that IS guarded.
    #
    # Structure comes from the mask, so a `(`/backquote still present there is
    # structural by construction — one inside quotes was already replaced. A
    # `)` with no opener is a `case` pattern terminator, not a close, and is
    # left alone. Over-collapsing can only HIDE a construct in this view, which
    # qline still reports; that asymmetry is why the filler is `~` rather than a
    # letter, so a collapsed run can never extend an option cluster it is
    # adjacent to.
    #
    # A PROCESS substitution is the one paren the shell does NOT make a separate
    # word: it expands to `/dev/fd/N` and concatenates onto the word it touches,
    # which is why `echo -e<(printf x)` passes the single argument
    # `-e/dev/fd/63` and must stay unflagged. Collapsing its body erased the `(`
    # that tells the `echo -e` boundary those two are one word, and the line was
    # newly reported. It is recognized by the `<`/`>` immediately before the
    # paren and kept verbatim, so only the frames that DO become their own word
    # collapse.
    function collapse_subs(q, m,   i, c, r, len, kinds, nc, inbt, prev, top) {
      r = ""
      kinds = ""
      nc = 0
      inbt = 0
      len = length(m)
      for (i = 1; i <= len; i++) {
        c = substr(m, i, 1)
        if (c == BT) {
          inbt = !inbt
          r = r "~"
          continue
        }
        if (c == "(") {
          prev = ""
          if (i > 1) prev = substr(m, i - 1, 1)
          if (prev == "<" || prev == ">") {
            kinds = kinds "S"
          } else {
            kinds = kinds "C"
            nc++
          }
        } else if (c == ")" && kinds != "") {
          top = substr(kinds, length(kinds), 1)
          if (nc > 0 || inbt) r = r "~"
          else r = r substr(q, i, 1)
          if (top == "C") nc--
          kinds = substr(kinds, 1, length(kinds) - 1)
          continue
        }
        if (nc > 0 || inbt) r = r "~"
        else r = r substr(q, i, 1)
      }
      return r
    }
    # ---- Word layer (#1551 stage 1) ----
    # The mask decides which CHARACTER is quoted; these functions decide which
    # run of characters is one shell WORD and what that word becomes after
    # quote removal (2.6.7). They are the first slice of the word-aware layer
    # #1551 records: word delimitation reads the MASK (a quoted space never
    # splits a word, a masked separator never splits a command), and quote
    # removal runs on the word text alone, which starts in the unquoted state
    # by construction — its left boundary is structural.
    #
    # First consumer: `--` (end-of-options). `stat -- -c` passes `-c` as a
    # FILE OPERAND, so reporting it was a false positive; the same marker on
    # a fallback the guard trusts (`|| stat -- -f`) means the ladder has NO
    # real BSD call, so trusting it failed OPEN. The feature was implemented
    # three times inside #1544 and withdrawn whole (caecb44) because each
    # partial answer traded the false positive for a fail-open:
    #   stat -- -c; stat -c "%s" "$f"      later real call went unreported
    #   printf -- "%s" "$(stat -c ...)"    outer marker hid the nested call
    #   stat -c "%s" "$f" || stat "--" -f  guard trusted an -f that names a file
    # What was missing each time is exactly the word layer: per-invocation
    # scope (the marker word must sit between the command word of THIS hit
    # and its matched option, never reach a nested frame), resumed matching
    # (already provided by has_unguarded blanking), and quoted-word
    # recognition (the double-quoted, single-quoted, backslash and ANSI-C
    # spellings of the marker all unquote to it).
    #
    # Both directions read a TRUSTED input, so both err toward over-flag:
    #   - the REPORTING side suppresses a hit only on a word that STATICALLY
    #     unquotes to exactly `--`. A word carrying an expansion (`$marker`),
    #     a substitution frame, or undecoded escape content is never a marker
    #     here — variable indirection sits outside the scope of this gate
    #     throughout (#1513), and the residue direction is a reportable false
    #     positive with the one-line `portability-ok:` escape, never a
    #     fail-open;
    #   - the GUARD side rejects a fallback whenever such a word precedes the
    #     BSD option, and scans FLAT — a `--` inside a `|| y=$(stat -- -f)`
    #     frame belongs to the command of the fallback itself and still
    #     rejects. A wrongly rejected guard is an over-flag with the same
    #     escape.
    function is_wordbreak(mc) { return index(" \t;&|()<>" NL BT, mc) > 0 }
    function word_start(m, pos,   i) {
      for (i = pos; i > 1; i--)
        if (is_wordbreak(substr(m, i - 1, 1))) return i
      return 1
    }
    function word_end(m, pos,   i, len) {
      len = length(m)
      for (i = pos; i < len; i++)
        if (is_wordbreak(substr(m, i + 1, 1))) return i
      return len
    }
    # POSIX quote removal (2.6.7) over ONE word: quote characters go, content
    # stays. A `$` directly before a quote (the ANSI-C and locale quoting
    # forms) is removed with it, so those forms are quote OPENERS here; their
    # content is NOT decoded (an octal `\055\055` spelling stays escaped), so
    # an escape-spelled marker fails the `--` comparison on both sides — no
    # suppression (safe) and no guard rejection (accepted residue, same
    # indirection class as a marker held in a variable).
    function unquote_word(w,   i, c, n, st, r, len) {
      r = ""
      st = "U"
      len = length(w)
      for (i = 1; i <= len; i++) {
        c = substr(w, i, 1)
        if (st == "S") {
          if (c == SQ) st = "U"
          else r = r c
          continue
        }
        if (st == "D") {
          if (c == DQ) { st = "U"; continue }
          if (c == BS) {
            n = substr(w, i + 1, 1)
            # 2.2.3: in double quotes a backslash is removed only before the
            # characters it can there escape; before anything else it stays.
            if (n == DQ || n == "$" || n == BT || n == BS) { r = r n; i++ }
            else r = r c
            continue
          }
          r = r c
          continue
        }
        if (c == "$" && (substr(w, i + 1, 1) == SQ || substr(w, i + 1, 1) == DQ)) continue
        if (c == SQ) { st = "S"; continue }
        if (c == DQ) { st = "D"; continue }
        if (c == BS) { i++; if (i <= len) r = r substr(w, i, 1); continue }
        r = r c
      }
      return r
    }
    # dashdash_between — does a whole ARGV word inside [from, to] statically
    # unquote to `--`? Reporting-side trust rules:
    #   - a structural separator ABORTS: the extent spans more than one
    #     command (the gap of the sed token can cross `;`), so marker
    #     ownership is undecidable and the hit stays reported;
    #   - a nested `$(…)`/`(…)`/backquote frame is skipped whole and TAINTS
    #     its word — a marker inside it belongs to the nested command
    #     (`grep "$(printf -- x)" -P` keeps its hit), and a word gluing a
    #     frame could expand to anything, so it never suppresses;
    #   - a REDIRECTION target is not an argv word: in `stat > -- -c "%s"`
    #     the `--` names the file stdout goes to and `-c` stays a real
    #     option, so the operator (fd digits included) and its target word
    #     are dropped, never compared. A bash `&>` reaches here through the
    #     `&`-then-`>` peek; a plain control `&` still aborts above it.
    function dashdash_between(view, m, from, to,   i, c, w, tainted, depth) {
      w = ""
      tainted = 0
      for (i = from; i <= to; i++) {
        c = substr(m, i, 1)
        if (c == "<" || c == ">" || (c == "&" && substr(m, i + 1, 1) == ">")) {
          w = ""
          tainted = 0
          while (i <= to && substr(m, i, 1) ~ /[<>&]/) i++
          while (i <= to && substr(m, i, 1) ~ /[ \t]/) i++
          while (i <= to && !is_wordbreak(substr(m, i, 1))) i++
          i--
          continue
        }
        if (c == ";" || c == "&" || c == "|" || c == NL) return 0
        if (c == "(") {
          depth = 1
          while (i < to && depth > 0) {
            i++
            c = substr(m, i, 1)
            if (c == "(") depth++
            else if (c == ")") depth--
          }
          if (depth > 0) return 0
          tainted = 1
          continue
        }
        if (c == BT) {
          i++
          while (i <= to && substr(m, i, 1) != BT) i++
          if (i > to) return 0
          tainted = 1
          continue
        }
        if (c == ")") return 0
        if (is_wordbreak(c)) {
          if (w != "" && !tainted && unquote_word(w) == "--") return 1
          w = ""
          tainted = 0
          continue
        }
        w = w substr(view, i, 1)
      }
      if (w != "" && !tainted && unquote_word(w) == "--") return 1
      return 0
    }
    # dashdash_demoted — is the OPTION this match ends in demoted to an
    # operand by a `--` word earlier in its own invocation? Anchored entirely
    # inside the matched extent: the extent starts at the command word and
    # cannot cross the separators its token gap excludes, which is what scopes
    # the marker to the invocation that owns it — a `--` belonging to an
    # outer command sits BEFORE `at` and is never examined, and a hit inside
    # a nested frame walks only that frame. Tokens whose match is not command-then-option
    # (the bare regex-escape classes, a literal `--perl-regexp`) never demote:
    # their match ends in the same word it starts in, or in a word that does
    # not unquote to an option, and `--` does not un-GNU a regex operand.
    # On demotion DD_OS holds the start offset of the demoted word so the
    # caller can discard the tail alone — the greedy gap can carry one match
    # THROUGH the marker, and an option before it is still real.
    function dashdash_demoted(view, m, at, mend,   ce, pe, os, oe) {
      pe = mend
      while (pe > at && is_wordbreak(substr(m, pe, 1))) pe--
      ce = word_end(m, at)
      if (pe <= ce) return 0
      os = word_start(m, pe)
      if (os <= ce + 1) return 0
      oe = word_end(m, pe)
      if (unquote_word(substr(view, os, oe - os + 1)) !~ /^-/) return 0
      DD_OS = os
      return dashdash_between(view, m, ce + 1, os - 1)
    }
    # fallback_proven — is the BSD-side `-f` of the ladder PROVEN to be an
    # option the fallback stat call actually parses? Anything the guard reads
    # in order to SUPPRESS a report is a trusted input, so this side must be
    # at least as strict as the reporting side (#1562). The regex established
    # the shape of the ladder; this walk, over [the `||` at opos, the option
    # word at os..oe], rejects what BSD getopt would never parse as `-f`
    # (FreeBSD/macOS stat(1): `stat [-FHhLnq] [-f format | -l | -r | -s |
    # -x] [-t timefmt] [file ...]` — option parsing stops at the first
    # operand, `--` ends it explicitly, `-f`/`-t` take an argument):
    #   - a word unquoting to `--` before the option: `|| stat -- -f` names
    #     a FILE `-f`, not an option — the shape that failed OPEN while `--`
    #     was not honored. Scanned FLAT, frames included: in
    #     `|| y=$(stat -- -f)` the marker belongs to the command of the
    #     fallback itself and still rejects;
    #   - an OPERAND word between the command name and the option:
    #     `|| stat "$f" -f "%z"` — BSD getopt stops at `"$f"`, so `-f` is
    #     never parsed (unlike GNU, which permutes). Redirections are not
    #     operands and are skipped whole, fd digits and target included,
    #     which is what keeps `|| stat 2>/dev/null -f "%z"` a real ladder;
    #   - an ARGUMENT-TAKING letter before `f` in its own cluster:
    #     `|| stat -tf "%z"` hands `f` to `-t` as its timefmt value;
    #   - a missing FORMAT argument: `-f` requires one, so a ladder ending
    #     at a bare `|| stat -f` runs no BSD call at all. Attached content
    #     (`-f%z`) satisfies it; otherwise a following word must exist
    #     before the command ends.
    # Every rejection here is an over-flag with the one-line
    # `portability-ok:` escape; accepting any of them ships a GNU-only call
    # whose "fallback" cannot run.
    function fallback_proven(q, m, opos, os, oe,   i, c, w, uw, phase, j, wantarg) {
      phase = 0
      wantarg = 0
      w = ""
      i = opos + 2
      while (i < os) {
        c = substr(m, i, 1)
        if (c == "<" || c == ">" || (c == "&" && substr(m, i + 1, 1) == ">")) {
          w = ""
          while (i < os && substr(m, i, 1) ~ /[<>&]/) i++
          while (i < os && substr(m, i, 1) ~ /[ \t]/) i++
          while (i < os && !is_wordbreak(substr(m, i, 1))) i++
          continue
        }
        if (is_wordbreak(c)) {
          if (w != "") {
            uw = unquote_word(w)
            if (wantarg) {
              # The previous word was a cluster whose detached `-t`/`-f`
              # takes an argument: THIS word is that argument, not an
              # operand and not an end-of-options marker, so
              # `|| stat -t "%Y" -f "%z"` stays a real ladder.
              wantarg = 0
            } else if (uw == "--") return 0
            else if (phase == 0) {
              # Before the command word only the shapes CMDPOS admitted can
              # appear — assignments, wrappers, group openers — so nothing
              # here is an operand of the stat call yet.
              if (uw ~ /(^|\/)stat$/) phase = 1
            } else if (uw !~ /^-/) return 0
            else if (uw ~ /^-[FHhLlnqrsx]*[ft]$/) wantarg = 1
          }
          w = ""
          i++
          continue
        }
        w = w substr(q, i, 1)
        i++
      }
      # A pending detached argument swallows the final word itself:
      # `|| stat -t -f "%z"` hands `-f` to `-t` as its timefmt, so the
      # ladder ends in an argument, not an option BSD getopt parses.
      if (wantarg) return 0
      uw = unquote_word(substr(q, os, oe - os + 1))
      if (uw !~ /^-[FHhLlnqrsx]*f/) return 0
      if (substr(uw, index(uw, "f") + 1) != "") return 1
      j = oe + 1
      while (substr(m, j, 1) ~ /[ \t]/) j++
      c = substr(m, j, 1)
      # The comment test reads the TEXT, not the mask: an inline comment is
      # masked to the same filler a quoted argument is, but only a comment
      # can put an unquoted `#` at a word start — that is why the mask
      # blanked it. A quoted argument starts at its quote character.
      if (c == "" || substr(q, j, 1) == "#" || index(";&|)" NL BT, c) > 0) return 0
      return 1
    }
    # SEG is the run between the GNU call and the `||`, and stops at a command
    # separator. Without it the two calls need not be in the same command at
    # all: `stat -c %s "$f"; true || stat -f %z "$f"` runs the GNU-only call
    # unconditionally and reaches the `||` from a LATER command. `;` and `|`
    # are excluded, and so is a CONTROL `&`, which backgrounds the GNU call and
    # hands the `||` to whatever follows. Redirections are kept, in BOTH
    # ampersand positions: `2>&1` and `<&-` put it last, bash `&>` and `&>>`
    # put it first, and neither ends the command (#1544).
    #
    # CMDPOS is everything allowed between that `||` and the BSD-side command
    # NAME for that command to be what the `||` actually runs: an optional
    # name= assignment prefix, an optional `$(` opening a command substitution,
    # and an optional invocation wrapper. `command` is the POSIX-specified one,
    # and `env` and a leading backslash reach the same real utility.
    #
    # PRE is what may sit between either command name and its own option: a
    # redirection does not change the argv the utility receives, so
    # `stat 2>/dev/null -f "%z" "$f"` is the same BSD call as `stat -f …`. Its
    # gap excludes the control operators for the same reason SEG does — a gap
    # that may swallow a `;` lets the guard be satisfied by a ladder belonging
    # to a later command.
    #
    # The TRUSTED side of that regex is re-checked by fallback_proven() after
    # it matches: a `stat -- -f` / `stat "--" -f` counterpart, an operand
    # before the `-f`, an argument-taking cluster letter ahead of it, or a
    # missing format argument each mean the "fallback" runs no BSD stat at
    # all, and each previously failed OPEN.
    # A `!` in front of the GNU call inverts its status, so the `||` fires when
    # the call SUCCEEDS and is skipped when it fails — the fallback never runs
    # on the dialect that needs it. A negated probe therefore has no guard at
    # all, however well-formed the ladder after it looks.
    function blanks(n,   s) {
      s = ""
      while (length(s) < n) s = s " "
      return s
    }
    # The `!` may be separated from the command name by the same prefixes
    # CMDPOS admits after a `||` — an invocation wrapper, an environment
    # assignment, or both — and none of them changes that the negation applies
    # to the pipeline (#1544). Matching only bare whitespace let
    # `! command stat -c …` and `! LANG=C stat -c …` read as unnegated.
    #
    # A `(` is NOT a reason to discard the negation, which is why it is absent
    # from the truncation class below. Whichever side of the paren the `!` sits,
    # the conclusion is the same — the fallback does not run on BSD:
    #   ! x=$(stat -c …) || stat -f …   the substitution exits with the status of
    #                                   stat, and `!` inverts it, so the `||` is
    #                                   skipped;
    #     x=$(! stat -c …) || stat -f … the inner `!` inverts it first.
    # Truncating at the `$(` lost the outer `!` and admitted the first shape
    # (#1544 review round 8). A `)` stays a boundary: an outer negation reaching
    # PAST a closed substitution is a shape this gate has never recognized, and
    # widening it is not what this finding is about.
    #
    # Over-detecting a negation costs a false positive; under-detecting one
    # admits an unguarded GNU-only call. This is the safe direction to widen.
    # The text after the last command boundary before <at>. Spelled as a
    # backward scan rather than a greedy `.*[;|&)]` match because a record can
    # now contain a NEWLINE, and whether `.` matches one is exactly the kind of
    # awk-implementation difference this gate must not depend on. A structural
    # newline is a boundary here for the same reason `;` is: inside a `$( )`
    # frame it ends the command. A quoted newline never reaches this — it is
    # neutralized to a space upstream.
    function after_last_boundary(h,   i, c) {
      for (i = length(h); i >= 1; i--) {
        c = substr(h, i, 1)
        if (c == ";" || c == "|" || c == "&" || c == ")" || c == NL)
          return substr(h, i + 1)
      }
      return h
    }
    function is_negated(q, at,   head) {
      head = after_last_boundary(substr(q, 1, at - 1))
      return head ~ ("(^|[[:space:]]|[(]|" BT ")![[:space:]]+" NEGOPEN PREFIXES "$")
    }
    # A `$( )` or backquote frame hands the `||` the status of the matched call
    # only when the frame IS what the enclosing command position runs — a plain
    # `name=$(…)` assignment. Used as an ARGUMENT, the enclosing command decides:
    # in `echo "$(stat -c …)" || stat -f …` the inner stat fails on BSD while
    # echo still succeeds, so the `||` never fires and the fallback never runs
    # (#1544). Same class as `x=$(stat -c …; true) || stat -f …`, reached through
    # the enclosing command rather than through a later one inside the frame.
    #
    # The lookback stops at `[;|&)]` and deliberately KEEPS `(` visible, unlike
    # is_negated(): that function asks what an outer `!` still governs and must
    # see past a frame, this one asks what ENCLOSES the frame and must see it.
    # A frame that IS the substitution of its own command still hands the `||`
    # a status only while it is the LAST one to run. For an assignment-only
    # command the exit status is the status of the last command substitution
    # performed (2.9.1), so a sibling frame BESIDE the matched one takes
    # ownership: in `x=$(stat -c …) y=$(true) || stat -f …` the `true` succeeds
    # after BSD stat fails and the fallback never runs (#1544).
    #
    # This asks the whole question rather than ruling out one neighbour shape:
    # the matched frame must be the status-determining frame of its command.
    # Three routes reach the same principle — a later command INSIDE the frame,
    # the command ENCLOSING it, and a later frame BESIDE it — and answering
    # them one at a time is what kept a further variant findable.
    #
    # The forward walk reads the MASK, not the text: a paren or backquote still
    # present there is structural by construction, so a `)` inside a quoted
    # argument cannot close the frame early. It stops at the first command
    # separator, which is the `||` itself in the shape this guards — anything
    # past that operator belongs to the fallback, not to the command whose
    # status the `||` tests.
    function status_swallowed(q, at, m,   head, before, opener, i, c, depth, len, closed) {
      head = after_last_boundary(substr(q, 1, at - 1))
      if (!match(head, ".*(\\$\\(|" BT ")")) return 0
      before = substr(head, 1, RLENGTH)
      opener = substr(before, length(before), 1)
      sub("(\\$\\(|" BT ")$", "", before)
      if (before !~ "^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=)?[[:space:]]*$") return 1
      len = length(m)
      closed = 0
      if (opener == BT) {
        # Backquotes do not nest without escaping, so the next one closes.
        for (i = at; i <= len; i++) {
          if (substr(m, i, 1) == BT) { closed = i; break }
        }
      } else {
        depth = 1
        for (i = at; i <= len; i++) {
          c = substr(m, i, 1)
          if (c == "(") depth++
          else if (c == ")") {
            depth--
            if (depth == 0) { closed = i; break }
          }
        }
      }
      if (closed == 0) return 0
      for (i = closed + 1; i <= len; i++) {
        c = substr(m, i, 1)
        if (c == "(" || c == BT) return 1
        if (c == ";" || c == "|" || c == "&") return 0
      }
      return 0
    }
    function is_guarded(q, p, at, m,   CMDPOS, SEG, PRE, NAME, QP, QL, lend, opos, os, i) {
      if (is_negated(q, at)) return 0
      # An opener after the `||` may be any spelling that makes the command
      # which follows it what the `||` actually runs: either substitution
      # spelling, or a subshell/brace group whose first command it is. The bare
      # `NAME=` (no value, no trailing space) is the `x=$(stat …)` shape.
      # `|| (stat -f …)` and `|| { stat -f …; }` were forced into an exemption
      # although the group genuinely executes the BSD fallback (#1544).
      #
      # `{` is a RESERVED WORD and only opens a group when a blank follows it,
      # so `|| {stat -f …` names a command `{stat` and runs no fallback at all;
      # admitting it without the blank was a fail-open (#1544). `(` is an
      # operator, needs no blank, and keeps none.
      CMDPOS = "\\|\\|[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=)?(\\$\\(|" BT "|\\(|\\{[[:space:]])?[[:space:]]*" PREFIXES
      SEG = "([^;|&" NL "]|[<>]&|&>|&&)*"
      # The fallback command word carries the same optional quote and path
      # spellings the token patterns already admit — quote removal invokes the
      # same BSD utility, so `|| "stat" -f …` and `|| "/usr/bin/stat" -f …` are
      # real ladders and were being forced into an exemption (#1544).
      NAME = "(\\$?[" SQ DQ "]|" BS BS ")?" "(/[^;|&[:space:]]*/)?"
      SEG = "([^;|&" NL "]|[<>]&|&>|&&)*"
      # A word inside PRE is any single argument that is not a control
      # operator. Excluding the operators matters as much here as in SEG: a gap
      # that may swallow a `;` lets the guard reach PAST the matched invocation
      # and be satisfied by a ladder belonging to a later command, which is the
      # line-wide behaviour this anchoring replaced.
      PRE = "(\\$?[" SQ DQ "]|" BS BS ")?" "[[:space:]]+([^;|&\n]*[[:space:]])?"
      # An OPTION word may carry quotes on BOTH sides of the ladder, exactly as
      # the shipped date/stat tokens admit: quote removal hands the utility the
      # same option either way, so `stat "-c" … || stat "-f" …` is one real
      # fallback ladder. Widening the token without widening the guard reported
      # every quoted-flag ladder as unguarded (#1544). The trusted side is safe
      # to widen for the same reason it is unsafe to trust `stat "--" -f`:
      # `"-f"` IS the option after quote removal, while `"--"` is the
      # end-of-options marker this gate does not honor at all.
      QP = QRUN
      QL = "([A-Za-z]|\\$?[" SQ DQ "]|" BS BS ")*"
      if (p ~ /readlink/) {
        return substr(q, 1, at + 7) ~ ("realpath" SEG CMDPOS NAME "readlink$")
      }
      # Scoped to the stat ladder, which looks FORWARD from a call whose failure
      # is what fires the `||`. The readlink guard looks BACKWARD from the last
      # rung — reached only because a portable attempt already failed — so where
      # its own status propagates to is not what that guard asks about.
      if (index(p, STATNAME) || index(p, "stat")) {
        if (status_swallowed(q, at, m)) return 0
        if (!match(substr(q, at), "^" STATNAME PRE QP "(-" QL "c|--format|--printf)" SEG CMDPOS NAME STATNAME PRE QP "-" QL "f")) return 0
        # match() so the EXTENT of the ladder is known: fallback_proven()
        # walks from its `||` to its final `-f` word. SEG admits no `|`, so
        # the first `||` inside the extent is the operator of the ladder
        # itself.
        lend = at + RLENGTH - 1
        opos = 0
        for (i = at; i < lend; i++)
          if (substr(m, i, 1) == "|" && substr(m, i + 1, 1) == "|") { opos = i; break }
        if (opos == 0) return 0
        os = word_start(m, lend)
        return fallback_proven(q, m, opos, os, word_end(m, lend))
      }
      return 0
    }
    # has_unguarded <view> <qline> <pattern> — does the view hold an occurrence
    # of the pattern that no same-line BSD ladder excuses?
    #
    # EVERY occurrence is evaluated, not just the first. A guarded ladder
    # earlier on the line says nothing about an unconditional call after it:
    # `stat -c … || stat -f … ; stat -c …` guards only the first pair, and
    # stopping at it reported the line clean (#1544). Consumed extents are
    # blanked in a scratch copy so the next `match()` finds the NEXT occurrence;
    # the guard still reads the untouched qline, and blanking preserves length
    # so offsets stay aligned.
    # Returns the OFFSET of the first such occurrence at or after `from`, or 0.
    # An offset rather than a yes/no because a joined record spans physical
    # lines and both the reported line number and the annotation scope are
    # decided by WHERE the hit sits; `from` lets the caller step past a hit its
    # own physical line excused and keep looking.
    function has_unguarded(view, q, p, m, from,   scan, st, len, at) {
      scan = view
      if (from > 1) scan = blanks(from - 1) substr(view, from)
      while (match(scan, p)) {
        st = RSTART
        len = RLENGTH
        at = st
        # Step over the leading word-boundary character the token consumed, so
        # the guard can anchor on the command name itself.
        if (substr(scan, at, 1) !~ /[A-Za-z]/) at++
        # A `--` word inside this invocation demotes the matched option to an
        # operand (dashdash_demoted); a demoted occurrence is discarded and
        # matching RESUMES, exactly as it does past a guarded one, so a later
        # real invocation on the same record is still evaluated. Only the
        # demoted word onward is discarded: the greedy gap can extend one
        # match through the marker (`grep -P pattern -- -P`), and the real
        # option before the marker must stay visible to the next match.
        if (dashdash_demoted(view, m, at, st + len - 1)) {
          scan = substr(scan, 1, DD_OS - 1) blanks(st + len - DD_OS) substr(scan, st + len)
          continue
        }
        if (!is_guarded(q, p, at, m)) return at
        scan = substr(scan, 1, st - 1) blanks(len) substr(scan, st + len)
      }
      return 0
    }
    # ---- bash-5.2 `&`-in-replacement class (!subst-replacement-ampersand) ----
    # skip_frame <line> <at> <limit> — the offset just PAST the nested frame
    # opening at <at> (any opener opens_frame() recognizes). Its body is not part
    # of the enclosing pattern or replacement text: a `/` inside `${x:-a/b}` is
    # data belonging to the inner expansion and never the separator, and a `&`
    # inside `$(a && b)` is inner command syntax, never a match reference.
    # Quoting inside the frame is tracked so a `)`/`}` in a string cannot close
    # it early. An UNTERMINATED frame runs to <limit>, which ends the scan with
    # no hit — the under-flag direction, and unreachable in practice because the
    # record loop only calls this once every frame the mask opened has closed.
    # opens_frame <line> <at> — does a nested frame open at <at>? A backquote,
    # a `$(` / `$((` / `${`, or a PROCESS substitution `<(` / `>(`.
    #
    # The process-substitution body is a COMMAND LIST, so an `&` or `&&` in it
    # is shell syntax and never a match reference, and the whole construct is
    # version-INdependent: verified on 5.3.15 that `v=aXb; "${v//X/<(a && b)}"`
    # yields `a/dev/fd/63b` with patsub_replacement both on AND off. Leaving it
    # out of the opener set walked into the body and reported the `&&` — a false
    # POSITIVE on portable code, the direction this class must not take. (This
    # is the one paren the collapse_subs() layer above deliberately keeps
    # verbatim, for the opposite reason: there it is not its own word. Here it
    # is not its own text.)
    function opens_frame(l, at,   c, n) {
      c = substr(l, at, 1)
      if (c == BT) return 1
      n = substr(l, at + 1, 1)
      if (c == "$" && (n == "(" || n == "{")) return 1
      if ((c == "<" || c == ">") && n == "(") return 1
      return 0
    }
    function skip_frame(l, at, limit,   c, o, cl, depth, st) {
      c = substr(l, at, 1)
      if (c == BT) {
        at++
        while (at <= limit && substr(l, at, 1) != BT) at++
        return at + 1
      }
      o = substr(l, at + 1, 1)
      if (o == "(") cl = ")"
      else cl = "}"
      at += 2
      depth = 1
      st = "U"
      while (at <= limit && depth > 0) {
        c = substr(l, at, 1)
        if (st == "S") {
          if (c == SQ) st = "U"
        } else if (c == BS) {
          at++
        } else if (c == SQ) {
          st = "S"
        } else if (c == DQ) {
          if (st == "D") st = "U"
          else st = "D"
        } else if (c == o) {
          depth++
        } else if (c == cl) {
          depth--
        }
        at++
      }
      return at
    }
    # amp_in_frame <line> <start> <end> — the offset of the first UNQUOTED `&`
    # in the replacement half of the `${…}` expansion spanning [start, end], or
    # 0 when the frame is not a pattern substitution or its replacement holds no
    # such `&`. <start> is the `$`, <end> the closing `}`.
    #
    # Grammar, verified against bash 5.3.15 rather than assumed:
    #   - the expansion is a substitution only when the character after the
    #     parameter name (and its optional `[…]` subscript) is `/`. That is what
    #     keeps `${var:-a/b/&}`, `${var#*/}`, `${var%/*}` and `${var:0:1}` out:
    #     their operator is not `/`, so every `/` and `&` in them is ordinary
    #     word text. `${#var}` is a length and can never be a substitution;
    #   - one optional `/` (global) or `#`/`%` (anchored) may follow the
    #     operator before the pattern begins;
    #   - the pattern ends at the FIRST `/` that is unquoted, unescaped and not
    #     inside a nested frame — not the last. `v=aXbXc; "${v//X/Y/Z}"` yields
    #     `aY/ZbY/Zc`, so the pattern is `X` and the replacement is `Y/Z`; a
    #     last-slash reading would have missed the `&` in `${v//X/b&/c}`. A
    #     quoted or backslash-escaped slash is NOT the separator
    #     (`s=a/b; "${s//"/"/-}"` and `"${s//\//-}"` both yield `a-b`), while a
    #     `[…]` bracket expression does NOT protect one (`"${p//[/]/-}"` leaves
    #     `a/b` untouched, so the pattern was `[`);
    #   - a frame with NO separator is the DELETION form `${var//pat}` and has
    #     no replacement to flag;
    #   - inside the replacement, only an `&` in the UNQUOTED state is a match
    #     reference. A backslash-escaped `\&`, a double-quoted one and a
    #     single-quoted one are each a literal ampersand on 5.3.15 — the manual
    #     says "Quoting any part of string inhibits replacement in the
    #     expansion of the quoted portion" — and none of them is flagged. `\&`
    #     is the spelling the failure message recommends, and the evidence for
    #     that is worth separating from what was inferred. BASH_COMPAT is NOT a
    #     pre-5.2 oracle for this rule — a bare `&` still expanded at every
    #     level down to 32 on 5.3.15, so the option is not compat-gated. What
    #     the ladder DOES establish is that the backslash before an `&` is
    #     removed even under the pre-4.3 quote-removal regime (tested at 32, 42,
    #     44, 50, 51 and the default); the manual supplies the rest, stating the
    #     backslash is removed in order to permit a literal `&`. The QUOTED
    #     spellings are the ones with a version quirk of their own (compat42:
    #     "The replacement string in double-quoted pattern substitution does not
    #     undergo quote removal, as it does in versions after bash-4.2"), which
    #     leaves the quote characters in the output on the older regime — a
    #     reason to prefer `\&`, not a reason to flag them.
    #
    # KNOWN LIMITS, all in the under-flag direction and all the same indirection
    # class this gate declares out of scope throughout (#1513):
    #   - an `&` that ARRIVES by expansion is undetectable here. The rule is
    #     applied after the replacement expands, so an `&` held in a variable
    #     and an `&` in the OUTPUT of a `$(…)` inside the replacement both
    #     reference the match at run time (verified on 5.3.15: for `v=aXb`, a
    #     replacement of `$(printf p&q)` — the ampersand produced by the
    #     substitution — yields `apXqb`). The manual says the same thing from
    #     the quoting side: quoting inhibits replacement "including replacement
    #     strings stored in shell variables";
    #   - a substitution assembled from fragments before use, exactly as the
    #     script header records for the ERE classes;
    #   - a parameter spelling this walk does not recognize (a name that is not
    #     an identifier, a digit run, or one of `@ * ? $ ! - #`) is skipped.
    function amp_in_frame(l, s, e,   i, c, st, sep, named) {
      i = s + 2
      if (i > e - 1) return 0
      c = substr(l, i, 1)
      # A `#` straight after `${` is USUALLY the length operator — but `#` is
      # also the special parameter holding the positional-argument count, and
      # bash resolves the ambiguity by what FOLLOWS it. When that is a `/`, no
      # parameter name can be starting, so the `#` is the parameter itself and
      # the rest is a real pattern substitution. Measured on 5.3.15 with two
      # positional parameters: `${#//2/&}` yields `2` with patsub_replacement on
      # and `&` with it off — the exact divergence this class exists for, which
      # an unconditional bail reported clean. `${#}`, `${##}`, `${#v}` and
      # `${#arr[@]}` all keep a non-`/` successor and stay length expansions.
      named = 1
      if (c == "#") {
        if (substr(l, i + 1, 1) != "/") return 0
        i++
        named = 0
      } else if (c == "!") i++
      if (named) {
        c = substr(l, i, 1)
        if (c ~ /[A-Za-z_]/) {
          while (i < e && substr(l, i, 1) ~ /[A-Za-z0-9_]/) i++
        } else if (c ~ /[0-9]/) {
          while (i < e && substr(l, i, 1) ~ /[0-9]/) i++
        } else if (c ~ /[@*?$!-]/) {
          i++
        } else return 0
      }
      if (substr(l, i, 1) == "[") {
        sep = 1
        i++
        while (i < e && sep > 0) {
          c = substr(l, i, 1)
          if (c == "[") sep++
          else if (c == "]") sep--
          i++
        }
        if (sep > 0) return 0
        sep = 0
      }
      if (substr(l, i, 1) != "/") return 0
      i++
      c = substr(l, i, 1)
      if (c == "/" || c == "#" || c == "%") i++
      # Pattern half: walk to the separator.
      st = "U"
      sep = 0
      while (i <= e - 1) {
        c = substr(l, i, 1)
        if (st == "S") {
          if (c == SQ) st = "U"
          i++
          continue
        }
        if (c == BS) { i += 2; continue }
        if (c == SQ) { st = "S"; i++; continue }
        if (c == DQ) {
          if (st == "D") st = "U"
          else st = "D"
          i++
          continue
        }
        if (opens_frame(l, i)) {
          i = skip_frame(l, i, e - 1)
          continue
        }
        if (st == "U" && c == "/") { sep = i; break }
        i++
      }
      if (sep == 0) return 0
      # Replacement half: the first unquoted `&`.
      i = sep + 1
      st = "U"
      while (i <= e - 1) {
        c = substr(l, i, 1)
        if (st == "S") {
          if (c == SQ) st = "U"
          i++
          continue
        }
        if (c == BS) { i += 2; continue }
        if (c == SQ) { st = "S"; i++; continue }
        if (c == DQ) {
          if (st == "D") st = "U"
          else st = "D"
          i++
          continue
        }
        if (opens_frame(l, i)) {
          i = skip_frame(l, i, e - 1)
          continue
        }
        if (st == "U" && c == "&") return i
        i++
      }
      return 0
    }
    # subst_amp_hit <line> <from> — the SMALLEST offset at or after <from> at
    # which an unquoted replacement `&` sits, or 0. An offset rather than a
    # yes/no for the same reason has_unguarded() returns one: a joined record
    # spans physical lines, and both the reported line number and the annotation
    # scope are decided by WHERE the hit sits. Frames are recorded in closing
    # order, so the minimum is taken rather than the first found — a nested
    # expansion closes before the one containing it.
    function subst_amp_hit(l, from,   f, at, best) {
      best = 0
      for (f = 1; f <= NV; f++) {
        at = amp_in_frame(l, VS[f], VE[f])
        if (at >= from && at > 0 && (best == 0 || at < best)) best = at
      }
      return best
    }
    # A HEREDOC body is not shell code, so it can neither continue a command nor
    # leave a quote open for the next line to inherit. It still gets SCANNED —
    # this corpus writes real scripts through heredocs and the gate deliberately
    # matches inside literal text — but it never joins.
    #
    # Without this, one stray backquote or apostrophe in heredoc data opened a
    # frame that swallowed everything after it: a PowerShell settings body
    # containing `` "CustomRule`Path" `` joined 57 following lines into one
    # record and let a `grep` on one line reach a `-Path` on another (#1544).
    # The blind spot predates quote-joining; joining is what made its blast
    # radius a whole file instead of one line.
    #
    # The delimiter is read from the ORIGINAL text at a `<<` the mask says is
    # structural: it may be quoted (`<<"EOF"`), and the mask has already blanked
    # those quotes. `<<<` is a here-string, not a heredoc, and is skipped.
    function heredoc_delim(l, m, i, len, j, c, d, q) {
      len = length(m)
      for (i = 1; i < len; i++) {
        if (substr(m, i, 1) != "<" || substr(m, i + 1, 1) != "<") continue
        if (substr(m, i + 2, 1) == "<") { i += 2; continue }
        j = i + 2
        HD_STRIP = 0
        if (substr(l, j, 1) == "-") { HD_STRIP = 1; j++ }
        while (substr(l, j, 1) == " " || substr(l, j, 1) == "\t") j++
        q = ""
        if (substr(l, j, 1) == SQ || substr(l, j, 1) == DQ) { q = substr(l, j, 1); j++ }
        d = ""
        while (j <= length(l)) {
          c = substr(l, j, 1)
          if (q != "" && c == q) break
          if (q == "" && index(" \t;&|<>()" BT, c) > 0) break
          d = d c
          j++
        }
        if (d != "") return d
      }
      return ""
    }
    # phys_of <offset> — the physical-line index a record offset falls on.
    function phys_of(off,   k) {
      for (k = nphys; k >= 1; k--)
        if (off >= physoff[k]) return k
      return 1
    }
    # phys_text <index> — that physical line as it was read, so an annotation
    # is scoped to the line carrying it rather than to the whole joined record.
    function phys_text(k) {
      if (k >= nphys) return substr(logical, physoff[k])
      return substr(logical, physoff[k], physoff[k + 1] - physoff[k] - 1)
    }
    # Pass 1: collect active ERE patterns from the token list, plus the `!name`
    # lines that activate a script-implemented class (see the script header).
    # An UNRECOGNIZED `!name` fails closed: ignoring it would let a typo in the
    # shipped list, or in a caller override, silently disable a whole class
    # while the run still reported clean — the one outcome the contract of this
    # gate forbids everywhere else.
    FNR == NR {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/) next
      if (substr(line, 1, 1) == "!") {
        if (line == AMPTOK) { CLS_AMP = 1; ncls++; next }
        printf "Error: unknown script-implemented class in token list: %s\n", line > "/dev/stderr"
        FATAL = 1
        exit 2
      }
      patterns[++np] = line
      next
    }
    # scan_logical <text> <first-line-number> <mask> — evaluate ONE logical line.
    function scan_logical(line, lineno, mask,   is_cmt, annotated_above, qline, cline, i) {
      is_cmt = is_comment(line)
      annotated_above = pending_annot
      if (is_cmt) {
        if (is_annotated(line)) pending_annot = 1
      } else {
        pending_annot = 0
      }
      # Construct matching skips comment-only lines — see script header.
      if (is_cmt) return
      qline = neutralize(line, mask)
      cline = collapse_subs(qline, mask)
      if (!joined && (is_annotated(line) || annotated_above)) return
      for (i = 1; i <= np; i++) {
        if (report_hit(line, lineno, patterns[i], annotated_above,
          has_unguarded(qline, qline, patterns[i], mask, 1), qline, qline, mask, "ere")) continue
        report_hit(line, lineno, patterns[i], annotated_above,
          has_unguarded(cline, qline, patterns[i], mask, 1), cline, qline, mask, "ere")
      }
      # The script-implemented class reads the ORIGINAL record text, because the
      # `&` it looks for is blanked on both derived views. It runs HERE, below
      # the comment-skip and annotation returns above, so that it inherits every
      # escape this function applies to the ERE classes; hoisting it above those
      # returns would silently lose all of them.
      if (CLS_AMP)
        report_hit(line, lineno, AMPTOK, annotated_above,
          subst_amp_hit(line, 1), line, qline, mask, "amp")
    }
    # report_hit — print the first hit whose OWN physical line is unexcused,
    # stepping past any the annotation on that line covers. Returns 1 if
    # anything was printed, so the second view is only consulted when the first
    # found nothing (one report per pattern per record, as before).
    # (Definition below; next_hit() has to be declared first because report_hit()
    # advances through it.)
    #
    # next_hit — the next occurrence at or after <from>, dispatched by CLASS
    # KIND. awk has no function references, so the kind is passed explicitly at
    # every call site rather than defaulted: a dropped argument arrives as the
    # empty string, and a kind that defaulted to the ERE finder would make the
    # script-implemented class report its first hit and then stop looking, with
    # the suite still green.
    function next_hit(kind, view, q, p, m, from) {
      if (kind == "amp") return subst_amp_hit(view, from)
      return has_unguarded(view, q, p, m, from)
    }
    # report_hit — see the doc block above next_hit().
    function report_hit(line, lineno, p, annotated_above, off, view, q, m, kind,   k) {
      # A backslash continuation removes the newline, so its physical lines are
      # one line in the strongest sense: the record is reported whole, at its
      # first line number, exactly as before. Only a quote-joined record, whose
      # newlines survive, is attributed per physical line.
      if (!joined) {
        if (off > 0) { hits[++nhits] = sprintf("%d: %s -> %s", lineno, p, line); return 1 }
        return 0
      }
      while (off > 0) {
        k = phys_of(off)
        # Every escape the gate offers is evaluated against the physical line
        # the hit sits on. Comment-skip included: a `#` line inside a quoted
        # embedded program is still prose, and leaving it to the record — whose
        # first line opened the quote and is therefore never a comment — newly
        # flagged the documentation inside this very script.
        if (!is_comment(phys_text(k)) &&
          !is_annotated(phys_text(k)) &&
          !annot_block_above(k, annotated_above)) {
          hits[++nhits] = sprintf("%d: %s -> %s", physno[k], p, phys_text(k))
          return 1
        }
        off = next_hit(kind, view, q, p, m, off + 1)
      }
      return 0
    }
    # The contiguous comment block directly above a physical line, read inside
    # the joined record. Falling off the top defers to the annotation state
    # carried in from the records before it.
    function annot_block_above(k, annotated_above,   j, t) {
      for (j = k - 1; j >= 1; j--) {
        t = phys_text(j)
        if (!is_comment(t)) return 0
        if (is_annotated(t)) return 1
      }
      return annotated_above
    }
    # Pass 2: scan the target file, ONE LOGICAL LINE at a time.
    #
    # A physical line is not a command in the other direction either (#1544): a
    # backslash-newline is removed before the shell tokenizes anything (2.2.1),
    # so `date \` + `-d tomorrow +%s` is one invocation whose GNU-only option
    # simply never appeared on the same record as its command name. Continued
    # lines are therefore accumulated and matched as the single line the shell
    # sees, and the hit is reported at the FIRST physical line number so a
    # continuation never shifts the numbering of anything after it.
    #
    # Whether the trailing backslash is a continuation or a quoted literal is
    # decided by the mask, not by a character test: it is one inside double quotes
    # (2.2.3 keeps backslash special before a newline) and NOT inside single
    # quotes (2.2.2 preserves every character), and `\\` at end of line is an
    # escaped backslash, not an escape. A COMMENT never continues — `#` runs to
    # the newline — for a comment-ONLY line through the is_comment() test here,
    # and for an INLINE comment through the mask, which stops at the `#` and so
    # never reaches a backslash sitting in comment text.
    # A QUOTE left open at end of record continues the command too, and for the
    # same reason: the shell has not finished the word, so the next physical
    # line belongs to this command. A `stat` whose quoted filename carries a
    # literal newline is one invocation whose GNU-only option simply never
    # shared a record with its command name, and the gate reported the file
    # clean (#1544).
    #
    # Unlike a backslash continuation the newline is KEPT — it is a character
    # of the quoted word, and inside a `$( )` frame it is a real command
    # separator that must stay structural.
    #
    # Joining makes a record span physical lines, so a hit is attributed back
    # to the physical line it actually sits on (PHYSOFF/PHYSNO below). Both the
    # reported line number and the `portability-ok:` scope follow that
    # attribution: without it one annotation anywhere inside a several-hundred
    # line embedded program would exempt the whole block, turning a join into a
    # fail-open far larger than the one it closes.
    {
      if (in_heredoc) {
        body = $0
        if (hd_strip) sub(/^\t+/, "", body)
        if (body == hd_delim) in_heredoc = 0
      } else if (!pending && $0 ~ /^[[:space:]]*#[[:space:]]*portability-scope:/) {
        # A whole-file declared scope — a fixture corpus belonging to this very
        # gate, which necessarily contains the constructs it detects as test
        # data. Anchored to a `#`-comment line whose content STARTS with the
        # token, so a doc-block sentence explaining the mechanism or a mention
        # inside a string literal never exempts a file for a reason it never
        # declared.
        #
        # Only a line the shell would read as a COMMENT counts, which means the
        # line must also open its own record. `pending` is still the state
        # carried IN from the lines before this one, so it is false exactly when
        # no quote, expansion, substitution or continuation is open — the one
        # context where a leading `#` starts a comment. Inside an open construct
        # the same characters are DATA, and honoring them let a value like
        # `x=<quote>foo` / `# portability-scope: bogus` / `bar<quote>` exempt an
        # entire file it never declared anything about (#1544). A heredoc body
        # is excluded by the branch above for the same reason.
        SCOPED = 1
      }
      if (pending) {
        # A backslash continuation removes the newline (2.2.1); a quoted one
        # keeps it, so each carries its own join separator.
        logical = logical pendsep $0
      } else {
        logical = $0
        logical_line = FNR
        nphys = 0
        joined = 0
        pending = 1
      }
      physoff[++nphys] = length(logical) - length($0) + 1
      physno[nphys] = FNR
      logical_mask = mask_quotes(logical)
      if (DANGLING_BS && !is_comment(logical)) {
        logical = substr(logical, 1, length(logical) - 1)
        pendsep = ""
        next
      }
      if (DANGLING_QUOTE && !is_comment(logical) && !in_heredoc) {
        pendsep = NL
        joined = 1
        next
      }
      scan_logical(logical, logical_line, logical_mask)
      pending = 0
      if (!in_heredoc) {
        hd_delim = heredoc_delim(logical, logical_mask)
        if (hd_delim != "") { in_heredoc = 1; hd_strip = HD_STRIP }
      }
    }
    # A file whose last line ends in a continuation still has one command left.
    #
    # An empty pattern set can only mean the token list failed to load — the
    # shipped one is never empty, and a caller overriding it wants SOME class
    # checked. Reporting clean in that state is the silent skip the contract
    # forbids, so it fails closed instead.
    END {
      # A pass-1 fatal (an unknown `!name`) reaches END through the awk `exit`;
      # re-reporting it as an empty pattern set would bury the real diagnostic.
      if (FATAL) exit 2
      if (pending) scan_logical(logical, logical_line, logical_mask)
      if (np == 0 && ncls == 0) {
        print "Error: token list loaded no active patterns" > "/dev/stderr"
        exit 2
      }
      # Hits are buffered rather than streamed so a declaration anywhere in the
      # file governs the whole file, as it always has, without the scan needing
      # a second pass to find it first.
      if (!SCOPED)
        for (h = 1; h <= nhits; h++) print hits[h]
    }
  ' "$TOKENS" "$awk_file"
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
if ((apply_baseline)) && ((${#baseline_entries[@]} > 0)); then
  for entry in "${baseline_entries[@]}"; do
    if [[ ! -f "$entry" ]]; then
      echo "STALE BASELINE: $BASELINE: '$entry' names a missing file — remove it" >&2
      violations=$((violations + 1))
      continue
    fi
    # --all visits every scannable file, so absence from baseline_still_hot
    # means the file scanned clean. Diff mode only sees changed files: an
    # untouched baseline entry is not re-proven here (changed-file scoping),
    # and is checked the next time it is edited or via --all.
    if [[ "$mode" == "--all" || -n "${files_in_scope[$entry]:-}" ]]; then
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
