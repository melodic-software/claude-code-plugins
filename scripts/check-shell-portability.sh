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
# This is a grep-level tripwire, not a semantic proof: it matches per
# PHYSICAL line, so a command split across a backslash line-continuation, or
# assembled into a variable before use, evades detection (tracked in #1513).
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
    BEGIN { SQ = "\047"; DQ = "\042"; BS = "\134" }
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
    # `[^;&|()\n]*` this replaces both over- and under-reached:
    #   - `stat "name;part" -c "%s"` was MISSED — the gap stopped at a `;`
    #     that is a filename character, not an operator;
    #   - `stat -- -c` and `date -- -d` were REPORTED — `--` ends option
    #     parsing, so the following word is an operand, not a flag;
    #   - `stat -c … ; stat -c … || stat -f …` reported NEITHER call — the
    #     guard was evaluated line-wide, so one guarded ladder anywhere on
    #     the line excused an unconditional GNU-only call before it.
    # Fixing any of those inside the ERE is not possible (quote state and
    # per-occurrence guard binding both need memory), and the `--` case needs
    # a word-is-not-`--` alternation that no reader could check. The state
    # belongs in this layer.
    #
    # Matching still runs against the ORIGINAL segment text, never the mask:
    # the GNU regex-escape classes (`\b`, `\s`, `\<`, …) legitimately live
    # INSIDE string literals — `grep -E "\bword"` — and must keep matching
    # there. The mask decides structure only.
    # (Both examples are spelled with double quotes because this awk program
    # is embedded in a single-quoted shell word; the single-quoted spellings
    # they stand for behave identically for the point being made.)
    #
    # Parentheses nest rather than separate: a `;` inside `$( )` belongs to
    # the inner command list (POSIX 2.6.3), and keeping the substitution
    # whole is also what lets `x=$(stat -c …) || y=$(stat -f …)` — the shape
    # lib/hook-utils.sh uses — still read as one fallback ladder.
    function mask_quotes(l,   i, c, m, q, len) {
      m = ""
      q = ""
      len = length(l)
      for (i = 1; i <= len; i++) {
        c = substr(l, i, 1)
        if (q == "") {
          # An unquoted backslash quotes exactly its successor (2.2.1), so
          # `\"` opens no string. Mask both, never running past the line end.
          if (c == BS) {
            m = m "Q"
            if (i < len) { m = m "Q"; i++ }
            continue
          }
          if (c == SQ || c == DQ) { q = c; m = m "Q"; continue }
          m = m c
          continue
        }
        if (q == DQ && c == BS) {
          m = m "Q"
          if (i < len) { m = m "Q"; i++ }
          continue
        }
        m = m "Q"
        if (c == q) q = ""
      }
      return m
    }
    # split_commands(line, mask, seg, sep) -> count. seg[i] is the ORIGINAL
    # text of command segment i; sep[i] is the control operator that
    # TERMINATED it ("" for the last). Binding each segment to its own
    # terminator is what lets a guard apply to the one invocation it actually
    # guards rather than to the whole line.
    function split_commands(l, m, seg, sep,   i, c, nx, pv, n, start, depth, len, op) {
      split("", seg)
      split("", sep)
      n = 1
      start = 1
      depth = 0
      len = length(m)
      for (i = 1; i <= len; i++) {
        c = substr(m, i, 1)
        if (c == "(") { depth++; continue }
        if (c == ")" && depth > 0) { depth--; continue }
        if (depth > 0) continue
        op = ""
        nx = substr(m, i + 1, 1)
        if (c == ";") {
          op = (nx == ";") ? ";;" : ";"
        } else if (c == "|") {
          op = (nx == "|") ? "||" : "|"
        } else if (c == "&") {
          # `2>&1` and `<&-` are redirections, not control operators — the
          # `&` there does not end the command. `&&` does, and so does a
          # lone `&`, which backgrounds what precedes it (so a `||` after it
          # binds to the NEXT command, not to the backgrounded one).
          pv = (i > 1) ? substr(m, i - 1, 1) : ""
          if (pv == ">" || pv == "<") continue
          op = (nx == "&") ? "&&" : "&"
        } else if (c == ")") {
          op = ")"
        } else {
          continue
        }
        seg[n] = substr(l, start, i - start)
        sep[n] = op
        i += length(op) - 1
        start = i + 2
        n++
      }
      seg[n] = substr(l, start)
      sep[n] = ""
      return n
    }
    # `--` ends option parsing, so every word after it is an operand however
    # flag-shaped it looks. Returning the text BEFORE it — searched on the
    # mask, so a literal `--` inside a string does not truncate — lets the
    # unchanged token EREs decide: if the construct still matches the prefix,
    # a real option was passed; if it only matched after the `--`, it was a
    # filename. GNU coreutils honors `--` per its shared option parser, and
    # BSD/macOS stat and date do the same (both document the
    # `utility [options] operands` form).
    function before_end_of_options(l, m,   cut) {
      if (!match(m, /(^|[[:space:]])--([[:space:]]|$)/)) return l
      cut = (substr(m, RSTART, 1) == "-") ? 0 : RSTART
      return substr(l, 1, cut)
    }
    # A guard is now anchored to ONE matched invocation rather than to the
    # physical line, so `stat -c … ; …` can no longer be excused by a ladder
    # further down the line.
    #
    # The two ladders run in OPPOSITE directions, and the matched segment
    # sits at a different end of each:
    #   - `stat -c … || stat -f …` — the token matches the GNU call, the
    #     FIRST rung of the ladder, so the guard looks FORWARD across the
    #     `||` that terminates the matched segment for the BSD counterpart.
    #   - `realpath … || readlink -f …` — the token matches `readlink -f`,
    #     which is the LAST rung, reached only when the portable attempt
    #     before it failed, so the guard looks BACKWARD across the `||`
    #     preceding the matched segment for the `realpath` attempt.
    #
    # CMDPOS is everything allowed between that `||` and the BSD-side command
    # NAME for that command to be what the `||` actually runs: an optional
    # name= assignment prefix, an optional `$(` opening a command
    # substitution, and an optional invocation wrapper. `command` is the
    # POSIX-specified one — it "shall execute" the named utility while
    # suppressing shell-function lookup — and `env`, plus a leading backslash
    # (which suppresses alias expansion), reach the same real utility. All
    # three were rejected before, forcing a hand-written exemption onto a
    # genuinely portable ladder (#1544).
    #
    # PRE is what may sit between either command name and its own option: a
    # redirection does not change the argv the utility receives, so
    # `stat 2>/dev/null -f "%z" "$f"` is the same BSD call as `stat -f …`.
    # Requiring the run to end in whitespace keeps the option a separate
    # argument. The optional closing quote after each command name mirrors
    # the token patterns, so a quoted `"stat"` still reads as the command.
    #
    # Keyed on index() of the command name rather than an anchored match, so
    # a token that grows a leading word boundary or a closing quote still
    # selects its own guard.
    function is_guarded_at(p, seg, sep, n, s,   CMDPOS, PRE) {
      CMDPOS = "^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=)?(\\$\\()?[[:space:]]*((command|env)[[:space:]]+|\\\\)?[[:space:]]*"
      # Built from SQ/DQ rather than written literally, because a single
      # quote cannot appear inside this single-quoted shell word.
      PRE = "[" SQ DQ "]?[[:space:]]+([^\n]*[[:space:]])?"
      if (p ~ /readlink/) {
        if (s <= 1 || sep[s - 1] != "||") return 0
        return (seg[s - 1] ~ /realpath/) && (seg[s] ~ (CMDPOS "readlink"))
      }
      if (index(p, "stat")) {
        if (s >= n || sep[s] != "||") return 0
        return seg[s + 1] ~ (CMDPOS "stat" PRE "-[A-Za-z]*f")
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
    # Pass 2: scan the target file.
    {
      line = $0
      is_cmt = is_comment(line)
      annotated_above = pending_annot
      if (is_cmt) {
        if (is_annotated(line)) pending_annot = 1
      } else {
        pending_annot = 0
      }
      # Construct matching skips comment-only lines — see script header.
      if (is_cmt) next
      mask = mask_quotes(line)
      nseg = split_commands(line, mask, seg, sep)
      # Same split over the mask itself, so each segment has a masked twin at
      # the same index for the `--` search (which must not see a quoted `--`).
      split_commands(mask, mask, smask, ssep)
      for (i = 1; i <= np; i++) {
        for (s = 1; s <= nseg; s++) {
          if (before_end_of_options(seg[s], smask[s]) !~ patterns[i]) continue
          if (is_annotated(line) || annotated_above) break
          if (is_guarded_at(patterns[i], seg, sep, nseg, s)) continue
          # One report per pattern per physical line: the reported text is
          # the whole line, so a second hit on it would print a duplicate.
          printf "%d: %s -> %s\n", FNR, patterns[i], line
          break
        }
      }
    }
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
