#!/usr/bin/env bash
# Shell-portability-lint gate (#1491): flags GNU-only shell constructs in
# changed **/*.sh files — a class no existing gate covers. `shellcheck` lints
# shell syntax/style; scripts/check-skill-portability.sh (#531) matches
# skill-coupling tokens (stack/forge/branch/tracker defaults) against changed
# *skill* files only. Neither has GNU-vs-BSD regex/flag vocabulary, and no
# runner in this repo's CI uses BSD userland (a Windows runner's Git Bash still
# ships GNU grep/sed, so it would not help either) — the exposure is macOS
# system grep/sed/date/stat/mktemp/sort, unreachable from any lane here.
#
#   scripts/check-shell-portability.sh <base-ref>   gate .sh files a PR changed
#   scripts/check-shell-portability.sh --all         audit every tracked .sh file
#   scripts/check-shell-portability.sh --paths F...   scan exactly these files
#
# WHAT is detected is data, not logic: the construct list lives in
# scripts/shell-portability-tokens.txt (override with
# SHELL_PORTABILITY_TOKENS), one ERE pattern per active line, so a reviewer
# re-catch is a one-line data edit. HOW a legitimate hit is excused is this
# script's job.
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
# line — backslash-continued physical lines are joined first — so a command
# assembled into a variable before use still evades detection (tracked in
# #1513).
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

usage() {
  printf 'usage: check-shell-portability.sh <base-ref> | --all | --paths FILE...\n' >&2
  exit 2
}

# is_scannable <path> — a shell file this gate is responsible for. Vendor/
# upstream-synced copies carry their own drift gate, not this contract.
is_scannable() {
  local f="$1"
  case "$f" in
  */vendor/*) return 1 ;;
  *.sh) return 0 ;;
  *) return 1 ;;
  esac
}

# Resolve the file set for the requested mode.
files=()
if (($# == 0)); then
  usage
fi

mode="$1"
case "$mode" in
--all)
  shift
  (($# == 0)) || usage
  while IFS= read -r f; do
    is_scannable "$f" && files+=("$f")
  done < <(find . -type f -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.git/*' | sed 's|^\./||' | sort)
  ;;
--paths)
  shift
  (($# > 0)) || usage
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
  if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
    printf 'Error: base ref %s is not a valid commit\n' "$base" >&2
    exit 2
  fi
  # NUL-delimited (-z) so a pathname Git would C-quote (non-ASCII bytes under
  # the default core.quotePath, or a literal quote/backslash) arrives verbatim
  # — a quoted path would miss the *.sh suffix check below and be silently
  # dropped, the exact silent exclusion the contract forbids.
  while IFS= read -r -d '' f; do
    is_scannable "$f" || continue
    [[ -f "$f" ]] || continue # a rename-away/deletion leaves nothing to scan
    files+=("$f")
  done < <(git diff --name-only --diff-filter=d -z "$base" -- '*.sh' | sort -z -u)
  ;;
esac

if ((${#files[@]} == 0)); then
  echo "No shell files in scope — nothing to gate."
  exit 0
fi

# scan_file <path> — print `LINE: token -> text` for each unexcused hit.
scan_file() {
  local file="$1"
  # A whole-file declared scope (the gate's own fixture/test corpus, which
  # necessarily contains the literal GNU-only constructs this gate detects as
  # test data — e.g. this script's own check-shell-portability.test.sh)
  # excuses every hit in the file; the declaration is visible in the diff.
  # Anchored to a genuine `#`-comment line whose content actually STARTS with
  # the token, not a bare substring match anywhere in the file — an
  # unanchored search would also match this very sentence (a doc-block
  # comment merely explaining the mechanism) or a `portability-scope:`
  # mention inside a string literal, wrongly exempting the whole file for a
  # reason it never declared. See #1513.
  if grep -qE '^[[:space:]]*#[[:space:]]*portability-scope:' -- "$file"; then
    return 0
  fi
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
      SQ = "\047"; DQ = "\042"; BS = "\134"; BT = "\140"
      SEPS = ";&|()" BT
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
      ASSIGN = "(([A-Za-z_][A-Za-z0-9_]*=[^;|&[:space:]]*|[0-9]*[<>][<>]?&?[^;|&[:space:]]*)[[:space:]]+)*"
      PREFIXES = ASSIGN "((command|env)[[:space:]]+)?" ASSIGN "(\\\\)?[[:space:]]*"
      # Characters a shell word may begin after, for the `#` comment test.
      # `)` is among them because it is a control operator, so `(cmd)# …`
      # comments out the rest of the record; omitting it left a commented-out
      # `|| stat -f` structural and it was accepted as a real guard (#1544).
      WORDSTART = " \t;&|()" BT
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
    function mask_quotes(l,   i, c, m, st, top, len) {
      m = ""
      DANGLING_BS = 0
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
        if (c == "$" && substr(l, i + 1, 1) == "(") {
          m = m "Q("
          st = st "P"
          i++
          continue
        }
        if (c == "$" && substr(l, i + 1, 1) == "{") {
          m = m "QQ"
          st = st "V"
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
        if (top == "V") {
          m = m "Q"
          if (c == SQ) st = st "S"
          else if (c == DQ) st = st "D"
          else if (c == "}") st = substr(st, 1, length(st) - 1)
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
        if (c == ")" && top == "P") {
          m = m c
          st = substr(st, 1, length(st) - 1)
          continue
        }
        m = m c
      }
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
        if (substr(m, i, 1) == "Q" && index(SEPS, c) > 0) r = r "Q"
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
    # `--` (end-of-options) is deliberately NOT honored — `stat -- -c` and
    # `date -- -d` are reported even though the flag-shaped word after the
    # marker is an operand. This is the documented over-flag direction, and
    # `portability-ok: <reason>` is the one-line escape.
    #
    # It was implemented and withdrawn. Honoring it correctly needs the marker
    # scoped to the invocation that owns it, resumed matching after a discarded
    # occurrence, and recognition of a quoted `"--"` word — and each partial
    # answer traded the false positive for a fail-OPEN, which is the worse
    # direction this gate is explicitly tuned against:
    #   stat -- -c; stat -c "%s" "$f"      later real call went unreported
    #   printf -- "%s" "$(stat -c ...)"    outer marker hid the nested call
    #   stat -c "%s" "$f" || stat "--" -f  guard trusted an -f that names a file
    # Tracked in #1562 rather than carried here half-built; that issue holds
    # the reproductions and what a correct implementation needs.
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
    # Known gap, same one the `--` withdrawal above describes, on the TRUSTED
    # side: a `stat "--" -f` counterpart is accepted as a fallback although the
    # `-f` names a file there. That direction fails OPEN, which is the argument
    # for honoring `--` properly rather than partially.
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
    function is_negated(q, at,   head) {
      head = substr(q, 1, at - 1)
      if (match(head, /.*[;|&)]/)) head = substr(head, RSTART + RLENGTH)
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
    function status_swallowed(q, at,   head, before) {
      head = substr(q, 1, at - 1)
      if (match(head, /.*[;|&)]/)) head = substr(head, RSTART + RLENGTH)
      if (!match(head, ".*(\\$\\(|" BT ")")) return 0
      before = substr(head, 1, RLENGTH)
      sub("(\\$\\(|" BT ")$", "", before)
      return before !~ "^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=)?[[:space:]]*$"
    }
    function is_guarded(q, p, at,   CMDPOS, SEG, PRE, NAME, QP, QL) {
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
      SEG = "([^;|&]|[<>]&|&>|&&)*"
      # The fallback command word carries the same optional quote and path
      # spellings the token patterns already admit — quote removal invokes the
      # same BSD utility, so `|| "stat" -f …` and `|| "/usr/bin/stat" -f …` are
      # real ladders and were being forced into an exemption (#1544).
      NAME = "[" SQ DQ "]?(/[^;|&[:space:]]*/)?"
      SEG = "([^;|&]|[<>]&|&>|&&)*"
      # A word inside PRE is any single argument that is not a control
      # operator. Excluding the operators matters as much here as in SEG: a gap
      # that may swallow a `;` lets the guard reach PAST the matched invocation
      # and be satisfied by a ladder belonging to a later command, which is the
      # line-wide behaviour this anchoring replaced.
      PRE = "[" SQ DQ "]?[[:space:]]+([^;|&\n]*[[:space:]])?"
      # An OPTION word may carry quotes on BOTH sides of the ladder, exactly as
      # the shipped date/stat tokens admit: quote removal hands the utility the
      # same option either way, so `stat "-c" … || stat "-f" …` is one real
      # fallback ladder. Widening the token without widening the guard reported
      # every quoted-flag ladder as unguarded (#1544). The trusted side is safe
      # to widen for the same reason it is unsafe to trust `stat "--" -f`:
      # `"-f"` IS the option after quote removal, while `"--"` is the
      # end-of-options marker this gate does not honor at all.
      QP = "[" SQ DQ "]*"
      QL = "[A-Za-z" SQ DQ "]*"
      if (p ~ /readlink/) {
        return substr(q, 1, at + 7) ~ ("realpath" SEG CMDPOS NAME "readlink$")
      }
      # Scoped to the stat ladder, which looks FORWARD from a call whose failure
      # is what fires the `||`. The readlink guard looks BACKWARD from the last
      # rung — reached only because a portable attempt already failed — so where
      # its own status propagates to is not what that guard asks about.
      if (index(p, "stat")) {
        if (status_swallowed(q, at)) return 0
        return substr(q, at) ~ ("^stat" PRE QP "(-" QL "c|--format|--printf)" SEG CMDPOS NAME "stat" PRE QP "-" QL "f")
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
    function has_unguarded(view, q, p,   scan, st, len, at) {
      scan = view
      while (match(scan, p)) {
        st = RSTART
        len = RLENGTH
        at = st
        # Step over the leading word-boundary character the token consumed, so
        # the guard can anchor on the command name itself.
        if (substr(scan, at, 1) !~ /[A-Za-z]/) at++
        if (!is_guarded(q, p, at)) return 1
        scan = substr(scan, 1, st - 1) blanks(len) substr(scan, st + len)
      }
      return 0
    }
    # Pass 1: collect active ERE patterns from the token list.
    FNR == NR {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/) next
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
      if (is_annotated(line) || annotated_above) return
      for (i = 1; i <= np; i++) {
        if (has_unguarded(qline, qline, patterns[i]) ||
          has_unguarded(cline, qline, patterns[i])) {
          printf "%d: %s -> %s\n", lineno, patterns[i], line
        }
      }
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
    {
      if (pending) {
        logical = logical $0
      } else {
        logical = $0
        logical_line = FNR
        pending = 1
      }
      logical_mask = mask_quotes(logical)
      if (DANGLING_BS && !is_comment(logical)) {
        logical = substr(logical, 1, length(logical) - 1)
        next
      }
      scan_logical(logical, logical_line, logical_mask)
      pending = 0
    }
    # A file whose last line ends in a continuation still has one command left.
    END { if (pending) scan_logical(logical, logical_line, logical_mask) }
  ' "$TOKENS" "$awk_file"
}

violations=0
for file in "${files[@]}"; do
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
    while IFS= read -r v; do
      echo "PORTABILITY: ${file}:${v}" >&2
      violations=$((violations + 1))
    done <<<"$out"
  fi
done

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
  exit 1
fi
echo "No unexcused GNU-only constructs in ${#files[@]} shell file(s)."
