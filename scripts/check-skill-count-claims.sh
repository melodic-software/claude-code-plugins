#!/usr/bin/env bash
# Check every prose claim about how many skills a plugin bundles against the
# number of skills that plugin actually has.
#
#   scripts/check-skill-count-claims.sh          discover: list every claim
#                                                 found, its site, the claimed
#                                                 count, the real count, and a
#                                                 verdict
#   scripts/check-skill-count-claims.sh --check  fail on any claim that
#                                                 disagrees with the tree, and
#                                                 on any stale exemption
#
# Why a gate rather than a proofread. These counts are hand-written assertions
# about the repository -- "bundling fourteen skills", "the other thirteen skills
# are zero-config" -- and nothing recomputes them when a skill is added. Adding
# one skill silently falsifies every sentence that counted the old set, in files
# nobody opens during that change.
#
# This is the numeric half of a defect the fleet already names on the prose
# side: `/docs-hygiene:audit-noise`'s `enum-list` shape flags "tables/lists
# hardcoding N specific consumers that drift on every add/remove" and prescribes
# runtime derivation. That skill advises; this gate holds. The two agree on the
# diagnosis and differ only in enforcement.
#
# CHANGELOG.md is deliberately NOT scanned. A changelog entry is a dated
# statement about a past state -- "the plugin now bundles twelve skills" was true
# of the release it describes, and rewriting it to match today's tree would
# falsify the history rather than fix a claim. Only surfaces that describe the
# CURRENT plugin are in scope: README.md, the plugin manifest, and skill bodies.
#
# Recognized claim forms are a closed set, listed under `Claim forms` below.
# The set is deliberately narrower than "any sentence containing a number and
# the word skills", because most such sentences are not composition claims at
# all ("gate one skill", "the Skill tool takes one skill per call", "nine skills
# moved into three new plugins"), and a gate that fires on those trains people
# to route around it. One form was evaluated and REJECTED: a definite-article
# reference (`the two skills ...`). It reads as a whole-set claim about as often
# as it reads as a claim about a named pair -- "the two skills this must not be
# confused with" -- so gating it would
# flag correct prose in a plugin whose count is right.
#
# WHAT THIS GATE DOES NOT COVER, said out loud so the coverage is not mistaken
# for completeness. Stale counts come in two classes and this gate holds one:
#
#   Class A -- repository-derivable. "The plugin has N skills." The denominator
#     is the tree, so a script can settle it. This gate.
#   Class B -- document-internal. "The four buckets", in a document that goes on
#     to define five. The denominator is the document's own structure, and which
#     structure a given count refers to is not mechanically recoverable -- a
#     prose count sits near headings, tables and lists that each have a different
#     cardinality, and picking the wrong one flags correct prose. No script in
#     this repo parses a document's structure to validate a claim the same
#     document makes; building that is a materially larger job than this one
#     and is deliberately not attempted here.
#
# SURFACES, not just classes: this gate reads FILES IN THE REPO. A count written
# anywhere else is class A -- derivable from the tree -- and still unguarded,
# because nothing here can see it. A pull-request description is the usual
# case. So when prose describing the CURRENT repo lives on GitHub rather than on disk --
# a PR or issue body, a wiki page -- derive its counts at write time or expect
# them to drift, and do not read a green gate as covering them.
#
# The dated-record carve-out stated above for CHANGELOG.md travels off-disk with
# the count. A GitHub release note states what was true of the release it
# describes, so its denominator is that tree, and later divergence is history
# rather than drift -- rewriting it to match today's tree would falsify it for
# exactly the reason the changelog is not scanned. Off-disk surfaces get the same
# current-state test as the scanned ones, not a broader one.
#
# Nothing else was scoped out WITHIN the files it reads. Counts of agents,
# commands and hooks would be class A too, and the grammar generalizes to them by
# swapping the noun -- but no plugin makes such a claim today (checked across
# every README and manifest), so the noun stays `skills` rather than shipping
# unexercised machinery.
#
# Direction is over-flag, not under-flag, within that closed set: a false
# positive costs one line in scripts/skill-count-claim-exemptions.txt with the
# reason recorded, and that file carries a stale-entry guard so it can only
# shrink. A missed true positive ships a wrong number to every reader of the
# plugin's front page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

exemptions_file="scripts/skill-count-claim-exemptions.txt"

number_words=(
  zero one two three four five six seven eight nine ten
  eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen
  twenty twentyone twentytwo twentythree twentyfour twentyfive
  twentysix twentyseven twentyeight twentynine thirty
)

declare -A word_to_int
for i in "${!number_words[@]}"; do
  word_to_int["${number_words[$i]}"]="$i"
done

int_to_word() {
  local n="$1"
  if ((n <= 20 || n == 30)); then
    printf '%s' "${number_words[$n]}"
  elif ((n < 30)); then
    printf 'twenty-%s' "${number_words[$((n - 20))]}"
  else
    printf '%d' "$n"
  fi
}

num_alt="$(
  IFS='|'
  printf '%s' "${number_words[*]}"
)"
num_re="(twenty-(one|two|three|four|five|six|seven|eight|nine)|${num_alt}|[0-9]+)"

# Claim forms. Each entry is `expected-basis:ERE`, where the basis says what the
# claimed number should equal: `total` for the plugin's whole skill set,
# `minus-one` for the "everything except this one" idiom. Every pattern captures
# the number in group 2 (group 1 is the leading context alternation), so the
# match loop can stay form-agnostic.
#
# POSIX ERE only -- no \b, \s or \w. Those are GNU extensions this repo's
# shell-portability gate rejects, and `[[ =~ ]]` honors the platform's regex
# engine, so a BSD userland would reinterpret them silently.
claim_forms=(
  'minus-one:(other)[[:space:]]+'"${num_re}"'[[:space:]]+skills?([^[:alnum:]]|$)'
  'total:(bundles|bundling|bundle|ships|shipping|comprises|comprising|contains|containing|holds|holding)[[:space:]]+'"${num_re}"'[[:space:]]+skills?([^[:alnum:]]|$)'
  'total:(toolkit|suite|collection|family|set|plugin|toolbox)[[:space:]]+of[[:space:]]+'"${num_re}"'[[:space:]]+skills?([^[:alnum:]]|$)'
  'total:(across)[[:space:]]+'"${num_re}"'[[:space:]]+skills?([^[:alnum:]]|$)'
  'total:(^|[^[:alnum:]])'"${num_re}"'[[:space:]]+skills?,[[:space:]]+one[[:space:]]+[[:alpha:]]'
  'total:(^[[:space:]]*[-+>]?[[:space:]]*)'"${num_re}"'[[:space:]]+skills?,'
  'total:(^[[:space:]]*|[.:;!?][[:space:]]+|[[:space:]]--[[:space:]]+)'"${num_re}"'[[:space:]]+skills?:'
)

norm_out=""
normalize_line() {
  local s="$1"
  s="${s//[\*\`_]/}"
  # Both spellings of a dash. A README carries the real UTF-8 character; a JSON
  # manifest carries the six-character escape for the same codepoint, because
  # plugin.json descriptions are JSON-encoded. A normalizer that handles one
  # spelling is blind on the other file class, and this gate reads both.
  #
  # bs is built here rather than typed inline: an editor or formatter that
  # normalizes escape sequences silently rewrites a literal backslash-u into the
  # character it denotes, which is exactly how the manifest branch got lost once.
  local bs=$'\134'
  s="${s//${bs}u2014/ -- }"
  s="${s//${bs}u2013/ -- }"
  s="${s//'—'/ -- }"
  s="${s//'–'/ -- }"
  norm_out="$s"
}

# Prints the integer, or nothing at all for a token this gate does not recognize
# as a number. It never returns non-zero: a helper that fails is a helper the
# caller has to invoke inside a condition, and `set -e` is disabled inside
# conditions (SC2310), so the errexit this script relies on would quietly stop
# applying to everything else on that line. An empty result is the signal.
to_int() {
  local raw="${1,,}"
  case "$raw" in
  [0-9]*)
    printf '%d' "$raw"
    ;;
  *)
    raw="${raw//-/}"
    if [[ -n "${word_to_int[$raw]+set}" ]]; then
      printf '%d' "${word_to_int[$raw]}"
    fi
    ;;
  esac
}

render_expected() {
  local claimed_raw="$1" expected="$2"
  case "${claimed_raw,,}" in
  [0-9]*)
    printf '%d' "$expected"
    ;;
  *)
    int_to_word "$expected"
    ;;
  esac
}

skill_count() {
  local plugin_dir="$1" n=0 skill_dir
  for skill_dir in "$plugin_dir"skills/*/; do
    [[ -f "${skill_dir}SKILL.md" ]] || continue
    n=$((n + 1))
  done
  printf '%d' "$n"
}

# Exemptions: `<repo-relative-path>|<exact substring of the claim line>`, with an
# optional trailing `# reason`. Matched on the substring rather than a line
# number so ordinary edits above the site cannot silently retire the entry.
exempt_keys=()
if [[ -f "$exemptions_file" ]]; then
  # `inline`: an entry is `<path>|<substring>`, never a regex, so a `#` anywhere
  # on the line opens the reason comment (scripts/lib/read-list.sh owns the two
  # comment families and why they must stay distinct).
  # shellcheck disable=SC2310  # the non-zero return IS the handled case; the library reports it
  read_list::into exempt_keys "$exemptions_file" --comments inline || exit 2
  for raw in ${exempt_keys[@]+"${exempt_keys[@]}"}; do
    [[ "$raw" == *"|"* ]] || {
      printf 'FAIL: %s line has no "|" separator: %s\n' "$exemptions_file" "$raw" >&2
      exit 2
    }
  done
fi

# Sets `exempt_hit` rather than returning a status, for the same SC2310 reason
# `to_int` prints rather than returns: the caller reads the global instead of
# invoking this inside an `if`, so errexit stays live around the call.
exempt_hit=0
mark_if_exempt() {
  local path="$1" line="$2" key sub
  exempt_hit=0
  for key in ${exempt_keys[@]+"${exempt_keys[@]}"}; do
    [[ "${key%%|*}" == "$path" ]] || continue
    sub="${key#*|}"
    if [[ "$line" == *"$sub"* ]]; then
      read_list::mark_used "$key"
      exempt_hit=1
      return
    fi
  done
}

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

claims_found=0
mismatches=0
exempted=0
report=()

for plugin_dir in plugins/*/; do
  plugin="${plugin_dir%/}"
  plugin="${plugin##*/}"
  actual="$(skill_count "$plugin_dir")"

  files=("${plugin_dir}README.md" "${plugin_dir}.claude-plugin/plugin.json")
  for skill_md in "${plugin_dir}"skills/*/SKILL.md; do
    [[ -f "$skill_md" ]] && files+=("$skill_md")
  done

  for file in "${files[@]}"; do
    [[ -f "$file" ]] || continue
    # Slurped rather than streamed through `done <"$file"`: the loop body
    # reports on the same path it is reading, which reads to ShellCheck as a
    # read-and-write of one file (SC2094).
    file_lines=()
    mapfile -t file_lines <"$file"
    for ((idx = 0; idx < ${#file_lines[@]}; idx++)); do
      lineno=$((idx + 1))
      line="${file_lines[idx]}"

      next=""
      if ((idx + 1 < ${#file_lines[@]})); then
        next="${file_lines[idx + 1]}"
      fi
      next="${next#"${next%%[![:space:]]*}"}"
      subjects=("$line")
      case "$next" in
      '' | '#'* | '|'* | '```'* | '~~~'* | '---'*) ;;
      *) subjects+=("$line $next") ;;
      esac

      next_norm=""
      if ((${#subjects[@]} > 1)); then
        normalize_line "$next"
        next_norm="${norm_out,,}"
      fi

      for ((sub_idx = 0; sub_idx < ${#subjects[@]}; sub_idx++)); do
        subject="${subjects[sub_idx]}"
        # Case-folded BEFORE the cheap prefilter, not after: `[Ss]kill` rejects
        # an all-caps `SKILLS`, so prefiltering on the raw text would drop a
        # heading or emphasized sentence before the fold could reach it —
        # a prefilter that changes which claims are found is a hole, not an
        # optimization. The patterns spell their number words in lower case and
        # `[[ =~ ]]` has no case-insensitive flag, so folding the subject is the
        # portable way to catch every capitalization.
        lower="${subject,,}"
        case "$lower" in
        *skill*) ;;
        *) continue ;;
        esac
        normalize_line "$subject"
        norm="${norm_out,,}"

        for form in "${claim_forms[@]}"; do
          basis="${form%%:*}"
          pattern="${form#*:}"
          [[ "$norm" =~ $pattern ]] || continue
          # Captured BEFORE the duplicate guard below runs its own `=~`: a second
          # match attempt REPLACES BASH_REMATCH, and under `set -u` a failed one
          # leaves it empty, so reading group 2 afterwards aborts the script.
          claimed_raw="${BASH_REMATCH[2]}"
          if ((sub_idx > 0)); then
            dup=0
            for other in "${claim_forms[@]}"; do
              [[ "$next_norm" =~ ${other#*:} ]] || continue
              dup=1
              break
            done
            ((dup)) && continue
          fi
          claimed="$(to_int "$claimed_raw")"
          [[ -n "$claimed" ]] || continue

          expected="$actual"
          if [[ "$basis" == "minus-one" ]]; then
            expected=$((actual - 1))
            ((expected < 0)) && expected=0
          fi

          claims_found=$((claims_found + 1))
          if ((claimed == expected)); then
            report+=("ok|$file:$lineno|$plugin|$claimed_raw|$expected|$basis|$actual")
          else
            mark_if_exempt "$file" "$subject"
            if ((exempt_hit)); then
              exempted=$((exempted + 1))
              report+=("exempt|$file:$lineno|$plugin|$claimed_raw|$expected|$basis|$actual")
            else
              mismatches=$((mismatches + 1))
              report+=("MISMATCH|$file:$lineno|$plugin|$claimed_raw|$expected|$basis|$actual")
            fi
          fi
          break 2
        done
      done
    done
  done
done

if [[ "$mode" == "discover" ]]; then
  if ((claims_found == 0)); then
    echo "No skill-count claims found."
    exit 0
  fi
  printf '%-9s %-58s %-18s %s\n' "VERDICT" "SITE" "PLUGIN" "CLAIMED -> ACTUAL"
  for row in "${report[@]}"; do
    IFS='|' read -r verdict site plugin claimed expected basis actual_count <<<"$row"
    suffix=""
    [[ "$basis" == "minus-one" ]] && suffix=" (total minus one)"
    printf '%-9s %-58s %-18s %s -> %s%s\n' \
      "$verdict" "$site" "$plugin" "$claimed" "$(render_expected "$claimed" "$expected")" "$suffix"
  done
  printf '\n%d claim(s): %d mismatched, %d exempted.\n' \
    "$claims_found" "$mismatches" "$exempted"
  exit 0
fi

failed=0

for row in "${report[@]}"; do
  IFS='|' read -r verdict site plugin claimed expected basis actual_count <<<"$row"
  [[ "$verdict" == "MISMATCH" ]] || continue
  corrected="$(render_expected "$claimed" "$expected")"
  printf 'FAIL: %s claims "%s skill(s)" but plugin %s has %s.\n' \
    "$site" "$claimed" "$plugin" "$(int_to_word "$actual_count")" >&2
  if [[ "$basis" == "minus-one" ]]; then
    printf '      This is the "all but this one" idiom, so the number should be %s.\n' "$corrected" >&2
  fi
  printf '      Change it to "%s", or record a justified exception in %s as\n' "$corrected" "$exemptions_file" >&2
  printf '      "%s|<a distinctive substring of that line>  # why it is not a count claim".\n' "$site" >&2
  failed=1
done

stale_keys=()
read_list::stale_to stale_keys exempt_keys
for key in ${stale_keys[@]+"${stale_keys[@]}"}; do
  path="${key%%|*}"
  sub="${key#*|}"
  if [[ ! -f "$path" ]]; then
    read_list::stale_line "$exemptions_file" "$key" "exempts $path, which no longer exists. Drop the entry."
  else
    read_list::stale_line "$exemptions_file" "$key" \
      "exempts \"$sub\" in $path, but that no longer produces a mismatch; the prose was fixed or reworded, so drop the entry before it covers a future one."
  fi
  failed=1
done

if ((failed)); then
  exit 1
fi

printf 'All %d skill-count claim(s) match the tree (%d exempted).\n' \
  "$claims_found" "$exempted"
