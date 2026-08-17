# shellcheck shell=bash
# Shared noise-shape detectors for /audit-noise (sourceable; not invoked directly).
# Shape definitions and treatments: the skill's SKILL.md "Noise shapes and treatments".

audit_noise_trim_excerpt() {
  local line="$1"
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  if ((${#line} > 120)); then
    line="${line:0:117}..."
  fi
  # Prefer nameref when the caller wants to avoid a command-substitution subshell.
  if [[ -n "${2:-}" ]]; then
    local -n _audit_noise_excerpt_out="$2"
    _audit_noise_excerpt_out="$line"
    return 0
  fi
  printf '%s' "$line"
}

# Resolve configured convention roots once per process and export them.
# Calling this (or the legacy pattern helper) inside a command substitution used
# to set AUDIT_NOISE_CONTRACT_ROOT only in the subshell — so a configured
# contract root's bare reviews/handoffs/running-retros child was silently
# exempt against the lib's stated intent (auditor F6).
audit_noise_resolve_convention_roots() {
  if [[ -n "${AUDIT_NOISE_ROOTS_RESOLVED:-}" ]]; then
    return 0
  fi
  local pattern='\.work|docs/topics' key val yaml lib_dir
  yaml="${AUDIT_NOISE_REPO_ROOT:-.}/.claude/topic-docs.yaml"
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Default contract root matches the built-in pattern default.
  AUDIT_NOISE_CONTRACT_ROOT="${AUDIT_NOISE_CONTRACT_ROOT:-docs/topics}"
  if [[ -f "$yaml" ]]; then
    for key in memory_dir contract_dir; do
      val=$("$lib_dir/parse-concern-value.sh" "$yaml" "$key")
      if [[ "$key" == 'contract_dir' && -n "$val" ]]; then
        AUDIT_NOISE_CONTRACT_ROOT="$val"
      fi
      if [[ -n "$val" && "$val" != '.' && "$val" != '.work' && "$val" != 'docs/topics' ]]; then
        pattern+="|$(printf '%s' "$val" | sed "s/[.[\\*^\$()+?{|]/\\\\&/g")"
      fi
    done
  fi
  AUDIT_NOISE_ROOTS_PATTERN="$pattern"
  AUDIT_NOISE_ROOTS_RESOLVED=1
  export AUDIT_NOISE_ROOTS_PATTERN AUDIT_NOISE_CONTRACT_ROOT AUDIT_NOISE_ROOTS_RESOLVED
}

# Back-compat wrapper: ensure roots are resolved, then print the pattern.
# Prefer audit_noise_resolve_convention_roots + $AUDIT_NOISE_ROOTS_PATTERN in
# hot paths so the assignment cannot be lost to a subshell.
audit_noise_convention_roots_pattern() {
  audit_noise_resolve_convention_roots
  printf '%s' "$AUDIT_NOISE_ROOTS_PATTERN"
}

# Per-match ghost-ref scan: exemptions apply to each matched path, never to
# the whole line, so a convention token cannot mask a concrete ghost ref
# sharing its line. Angle-bracket slot variables (root followed by '<') are
# schema placeholders and never match the candidate pattern; the reserved
# concern-scoped roots (<memory_dir>/handoffs/, <memory_dir>/reviews/,
# <memory_dir>/running-retros/ — reserved first-level names under the memory
# root per docs/conventions/topic-docs/) are exempt only in bare form — a
# concrete child under them flags. Configured non-default roots from the
# concern file scan alongside the defaults. The bare-root exemption is for
# memory roots only — never for the contract root (default or configured).
audit_noise_line_has_ghost_ref() {
  local rest="$1" path root seg after roots
  audit_noise_resolve_convention_roots
  # Retired locations: stale even in placeholder form.
  [[ "$rest" == *'.claude/notes/'* ||
    "$rest" == *'.claude/handoffs/'* ||
    "$rest" == *'.claude/review/'* ]] && return 0
  roots="$AUDIT_NOISE_ROOTS_PATTERN"
  while [[ "$rest" =~ ($roots)/([a-z0-9][a-z0-9_-]*)/ ]]; do
    path="${BASH_REMATCH[0]}"
    root="${BASH_REMATCH[1]}"
    seg="${BASH_REMATCH[2]}"
    after="${rest#*"$path"}"
    # Bare-root exemption: nothing concrete after the trailing slash. A
    # sentence-ending period (`.work/running-retros/.`) starts with `.` but is
    # punctuation, not a hidden child — only `.` followed by a path segment
    # character counts as concrete (`.gitignore`-style names still flag).
    if [[ "$root" != 'docs/topics' && "$root" != "$AUDIT_NOISE_CONTRACT_ROOT" ]] &&
      [[ "$seg" == 'handoffs' || "$seg" == 'reviews' || "$seg" == 'running-retros' || "$seg" == 'overengineering' ]] &&
      { [[ ! "$after" =~ ^[A-Za-z0-9._-] ]] || [[ "$after" =~ ^\.([^A-Za-z0-9_-]|$) ]]; }; then
      rest="$after"
      continue
    fi
    return 0
  done
  return 1
}

# Append matching shape names into the nameref array (avoids a per-line
# command-substitution subshell in the detect hot loop).
# Ghost-ref scans an unwrap (ticks removed, content kept); other shapes scan a
# strip (inline-code spans removed) so schema examples do not self-match.
audit_noise_detect_shapes_into() {
  local -n _audit_noise_shapes_out="$1"
  local line="$2"
  local unwrapped="" stripped=""
  _audit_noise_shapes_out=()
  audit_noise_unwrap_backticks "$line" unwrapped
  audit_noise_strip_inline_code "$line" stripped
  if audit_noise_line_has_ghost_ref "$unwrapped"; then
    _audit_noise_shapes_out+=('ghost-ref')
  fi
  if [[ "$stripped" =~ ^##[[:space:]]+Why[[:space:]]+this[[:space:]]+file[[:space:]]+exists ]]; then
    _audit_noise_shapes_out+=('preamble')
  fi
  if [[ "$stripped" =~ [Ee]mpirically[[:space:]]+observed ]] ||
    [[ "$stripped" =~ [Ww]e[[:space:]]+pivoted[[:space:]]+from ]] ||
    [[ "$stripped" =~ [Ww]as[[:space:]]+renamed[[:space:]]+to ]] ||
    [[ "$stripped" =~ [Pp]re-convention ]] ||
    [[ "$stripped" =~ [Ll]egacy[[:space:]]+layout ]]; then
    _audit_noise_shapes_out+=('citation')
  fi
  if [[ "$stripped" =~ [Ff]ollowing[[:space:]]+(five|four|three|six|seven|eight|nine|ten|[0-9]+)[[:space:]]+(skills|consumers|agents|modules) ]]; then
    _audit_noise_shapes_out+=('enum-list')
  fi
  # Enum roster lines often wrap the slash-command in backticks; match the
  # unwrapped form so `- `/skill`` still counts after tick removal.
  if [[ "$unwrapped" =~ ^[[:space:]]*-[[:space:]]+/[a-z][a-z0-9_-]*[[:space:]]— ]]; then
    _audit_noise_shapes_out+=('enum-list')
  fi
  if [[ "$stripped" =~ [Pp]ath-scoped[[:space:]]+to ]] ||
    [[ "$stripped" =~ [Ll]oads[[:space:]]+on[[:space:]]+[Rr]ead[[:space:]]+of ]] ||
    [[ "$stripped" =~ [Aa]uto-loads[[:space:]]+when ]]; then
    _audit_noise_shapes_out+=('scope-meta')
  fi
  ((${#_audit_noise_shapes_out[@]} > 0))
}

# Emit zero or more shape names (one per line on stdout). Prefer
# audit_noise_detect_shapes_into in hot loops.
audit_noise_detect_shapes() {
  local shapes=()
  if audit_noise_detect_shapes_into shapes "$1"; then
    local s
    for s in "${shapes[@]}"; do
      printf '%s\n' "$s"
    done
    return 0
  fi
  return 1
}

audit_noise_shape_tier() {
  local shape="$1"
  case "$shape" in
  ghost-ref | preamble) printf '2' ;;
  citation | enum-list | scope-meta) printf '1' ;;
  *) printf '3' ;;
  esac
}

# Set nameref to the tier digit without a subshell.
audit_noise_shape_tier_into() {
  local shape="$1"
  local -n _audit_noise_tier_out="$2"
  case "$shape" in
  ghost-ref | preamble) _audit_noise_tier_out=2 ;;
  citation | enum-list | scope-meta) _audit_noise_tier_out=1 ;;
  *) _audit_noise_tier_out=3 ;;
  esac
}

# True when an ATX heading's visible title (any level) is an exempt section.
# Callers pass the text after the opening hashes; trailing closing hashes and
# surrounding whitespace are stripped here.
audit_noise_section_exempt() {
  local heading="$1"
  heading="${heading#"${heading%%[![:space:]]*}"}"
  heading="${heading%"${heading##*[![:space:]]}"}"
  # ATX may close with trailing hashes: "## Sources ##"
  if [[ "$heading" =~ ^(.*[^#[:space:]])[[:space:]]*#+[[:space:]]*$ ]]; then
    heading="${BASH_REMATCH[1]}"
  fi
  heading="${heading%"${heading##*[![:space:]]}"}"
  case "$heading" in
  "Recheck triggers" | "Cross-references" | "Sources" | "History" | "External authority") return 0 ;;
  *) ;;
  esac
  [[ "$heading" == *"amendment"* ]] && return 0
  return 1
}

# Remove backtick characters only (unwrap inline code) so path cites like
# `.work/foo/PLAN.md` still reach the ghost-ref detector.
audit_noise_unwrap_backticks() {
  local line="$1"
  local -n _audit_noise_unwrapped_out="$2"
  _audit_noise_unwrapped_out="${line//\`/}"
}

# Strip inline `code` spans entirely so citation / enum / scope detectors do
# not self-match examples. Fence blocks are skipped by the caller.
audit_noise_strip_inline_code() {
  local line="$1"
  local -n _audit_noise_stripped_out="$2"
  local out="" rest="$line" pre
  while [[ "$rest" == *'`'* ]]; do
    pre="${rest%%\`*}"
    rest="${rest#*\`}"
    if [[ "$rest" == *'`'* ]]; then
      out+="$pre"
      rest="${rest#*\`}"
    else
      # Unclosed tick — keep the remainder literally.
      out+="$pre\`$rest"
      rest=""
      break
    fi
  done
  out+="$rest"
  _audit_noise_stripped_out="$out"
}

# True when the line is a well-formed HTML opt-out marker comment (not a
# prose mention of the marker name).
audit_noise_is_ignore_line_marker() {
  [[ "$1" =~ ^[[:space:]]*\<!--[[:space:]]*markdown-discipline-ignore-line[[:space:]]*--\>[[:space:]]*$ ]] # portability-ok: bash [[ =~ ]] ERE escapes for literal < >, not GNU grep word-boundary
}

audit_noise_is_ignore_para_marker() {
  [[ "$1" =~ ^[[:space:]]*\<!--[[:space:]]*markdown-discipline-ignore[[:space:]]*--\>[[:space:]]*$ ]] # portability-ok: bash [[ =~ ]] ERE escapes for literal < >, not GNU grep word-boundary
}
