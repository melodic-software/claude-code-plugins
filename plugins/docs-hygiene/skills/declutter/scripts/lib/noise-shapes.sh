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

# Configured convention roots: when the consuming repo's concern file
# (.claude/topic-docs.yaml) overrides memory_dir/contract_dir, those roots
# are ghost-ref surfaces too. Resolved once per process; defaults always
# scan (a doc may cite the defaults regardless of local config).
declutter_convention_roots_pattern() {
  if [[ -z "${DECLUTTER_ROOTS_PATTERN:-}" ]]; then
    local pattern='\.work|docs/topics' key val yaml
    yaml="${DECLUTTER_REPO_ROOT:-.}/.claude/topic-docs.yaml"
    if [[ -f "$yaml" ]]; then
      for key in memory_dir contract_dir; do
        val=$(sed -n "s/^${key}:[[:space:]]*//p" "$yaml" | head -1)
        val="${val%%#*}"; val="${val//[[:space:]]/}"; val="${val%/}"
        val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
        if [[ "$key" == 'contract_dir' && -n "$val" ]]; then
          DECLUTTER_CONTRACT_ROOT="$val"
        fi
        if [[ -n "$val" && "$val" != '.' && "$val" != '.work' && "$val" != 'docs/topics' ]]; then
          pattern+="|$(printf '%s' "$val" | sed "s/[.[\\*^\$()+?{|]/\\\\&/g")"
        fi
      done
    fi
    DECLUTTER_ROOTS_PATTERN="$pattern"
  fi
  printf '%s' "$DECLUTTER_ROOTS_PATTERN"
}

# Per-match ghost-ref scan: exemptions apply to each matched path, never to
# the whole line, so a convention token cannot mask a concrete ghost ref
# sharing its line. Angle-bracket slot variables (root followed by '<') are
# schema placeholders and never match the candidate pattern; the reserved
# concern-scoped roots (<memory_dir>/handoffs/, <memory_dir>/reviews/) are
# exempt only in bare form — a concrete child under them flags. Configured
# non-default roots from the concern file scan alongside the defaults.
declutter_line_has_ghost_ref() {
  local rest="$1" path root seg after roots
  # Retired locations: stale even in placeholder form.
  [[ "$rest" == *'.claude/notes/'* ||
    "$rest" == *'.claude/handoffs/'* ||
    "$rest" == *'.claude/review/'* ]] && return 0
  roots="$(declutter_convention_roots_pattern)"
  while [[ "$rest" =~ ($roots)/([a-z0-9][a-z0-9_-]*)/ ]]; do
    path="${BASH_REMATCH[0]}"
    root="${BASH_REMATCH[1]}"
    seg="${BASH_REMATCH[2]}"
    after="${rest#*"$path"}"
    if [[ "$root" != 'docs/topics' && "$root" != "${DECLUTTER_CONTRACT_ROOT:-docs/topics}" ]] &&
      [[ "$seg" == 'handoffs' || "$seg" == 'reviews' ]] &&
      [[ ! "$after" =~ ^[A-Za-z0-9._-] ]]; then
      rest="$after"
      continue
    fi
    return 0
  done
  return 1
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
  if declutter_line_has_ghost_ref "$line"; then
    printf '%s\n' 'ghost-ref'
    found=1
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
