#!/usr/bin/env bash
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
  local bs=$'\134'
  s="${s//${bs}u2014/ -- }"
  s="${s//${bs}u2013/ -- }"
  s="${s//'—'/ -- }"
  s="${s//'–'/ -- }"
  norm_out="$s"
}

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

exempt_keys=()
if [[ -f "$exemptions_file" ]]; then
  # shellcheck disable=SC2310  # the non-zero return IS the handled case; the library reports it
  read_list::into exempt_keys "$exemptions_file" --comments inline || exit 2
  for raw in ${exempt_keys[@]+"${exempt_keys[@]}"}; do
    [[ "$raw" == *"|"* ]] || {
      printf 'FAIL: %s line has no "|" separator: %s\n' "$exemptions_file" "$raw" >&2
      exit 2
    }
  done
fi

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
