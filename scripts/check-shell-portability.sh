#!/usr/bin/env bash
# Shell-portability-lint gate (issue #1491): flags GNU-only shell constructs in
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
#   3. a whole-file `portability-scope: <reason>` declaration anywhere in the
#      file — for a file that IS this gate's own fixture/test corpus and so
#      necessarily contains the literal constructs it detects as test data
#      (this script's own check-shell-portability.test.sh uses it), not for
#      excusing a real shipped script's real coupling.
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
# This is a grep-level tripwire, not a semantic proof. Guard markers are seeded
# for the one class that needs one against the live corpus today (readlink -f);
# a further class enables its own guard here, proven against an `--all` audit
# first — see the token file's STAGED section.
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
  if grep -qE 'portability-scope:' -- "$file"; then
    return 0
  fi
  awk '
    function is_annotated(l) { return l ~ /portability-ok:/ }
    function is_comment(l) { return l ~ /^[[:space:]]*#/ }
    # Same-line auto-guard: a portable BSD-side attempt already co-located on
    # the hit line. Scoped to the one active class that needs it today
    # (readlink -f, guarded by a co-located realpath attempt — the shape
    # lib/hook-utils.sh already uses: `realpath ... || readlink -f ...`). A
    # further class enables its own marker here when it is activated (see the
    # token file STAGED section) — this is deliberately not a generic
    # heuristic, the same posture check-skill-portability.sh takes.
    function is_guarded(l) { return l ~ /realpath/ }
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
      for (i = 1; i <= np; i++) {
        if (line ~ patterns[i]) {
          if (is_annotated(line) || annotated_above) continue
          if (is_guarded(line)) continue
          printf "%d: %s -> %s\n", FNR, patterns[i], line
        }
      }
    }
  ' "$TOKENS" "$file"
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
