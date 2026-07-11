# shellcheck shell=bash
# Shared noise-shape detectors for /declutter (sourceable; not invoked directly).
# Shape definitions and treatments: the skill's SKILL.md "Noise shapes and treatments".

declutter_trim_excerpt() {
  local line="$1"
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  if ((${#line} > 120)); then
    line="${line:0:117}..."
  fi
  printf '%s' "$line"
}

declutter_is_slot_work_ref() {
  local line="$1"
  [[ "$line" == *'.work/<slug>'* || "$line" == *'.work/<sub-slug>'* || "$line" == *'.work/<TS>'* ]]
}

declutter_line_skipped() {
  local prev="$1" line="$2"
  [[ "$prev" == *'markdown-discipline-ignore'* ]] && return 0
  [[ "$line" == *'markdown-discipline-ignore'* ]] && return 0
  return 1
}

# Emit zero or more shape names (one per line on stdout).
declutter_detect_shapes() {
  local line="$1"
  local found=0
  if ! declutter_is_slot_work_ref "$line"; then
    if [[ "$line" =~ \.work/[a-z][a-z0-9_-]*/ ]]; then
      printf '%s\n' 'ghost-ref'
      found=1
    fi
  fi
  if [[ "$line" =~ ^##[[:space:]]+Why[[:space:]]+this[[:space:]]+file[[:space:]]+exists ]]; then
    printf '%s\n' 'preamble'
    found=1
  fi
  if [[ "$line" =~ [Ee]mpirically[[:space:]]+observed ]] ||
    [[ "$line" =~ [Ww]e[[:space:]]+pivoted[[:space:]]+from ]] ||
    [[ "$line" =~ [Ww]as[[:space:]]+renamed[[:space:]]+to ]] ||
    [[ "$line" =~ [Pp]re-convention ]] ||
    [[ "$line" =~ [Ll]egacy[[:space:]]+layout ]]; then
    printf '%s\n' 'citation'
    found=1
  fi
  if [[ "$line" =~ [Ff]ollowing[[:space:]]+(five|four|three|six|seven|eight|nine|ten|[0-9]+)[[:space:]]+(skills|consumers|agents|modules) ]]; then
    printf '%s\n' 'enum-list'
    found=1
  fi
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\`?/[a-z][a-z0-9_-]*\`?[[:space:]]— ]]; then
    printf '%s\n' 'enum-list'
    found=1
  fi
  if [[ "$line" =~ [Pp]ath-scoped[[:space:]]+to ]] ||
    [[ "$line" =~ [Ll]oads[[:space:]]+on[[:space:]]+[Rr]ead[[:space:]]+of ]] ||
    [[ "$line" =~ [Aa]uto-loads[[:space:]]+when ]]; then
    printf '%s\n' 'scope-meta'
    found=1
  fi
  return "$found"
}

declutter_shape_tier() {
  local shape="$1"
  case "$shape" in
  ghost-ref | preamble) printf '2' ;;
  citation | enum-list | scope-meta) printf '1' ;;
  *) printf '3' ;;
  esac
}

declutter_section_exempt() {
  local heading="$1"
  case "$heading" in
  "Recheck triggers" | "Cross-references" | "Sources" | "History" | "External authority") return 0 ;;
  *) ;;
  esac
  [[ "$heading" == *"amendment"* ]] && return 0
  return 1
}
