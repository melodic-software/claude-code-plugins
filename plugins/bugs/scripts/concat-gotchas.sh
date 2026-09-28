#!/usr/bin/env bash
# Concatenate ## Gotchas from the bugs config-cascade layers in layer order
# (user-global, team, local overlay). Form 1 (concatenate) per
# docs/conventions/config-cascade/consumer-gotchas.md (#3547).
#
# Usage: concat-gotchas.sh
# Env: HOME (user-global), CLAUDE_PROJECT_DIR (repo root; else git toplevel).
# Always exits 0 so a skill pre-compute injection cannot fail skill load.
set -u

extract_gotchas() {
  local file="$1"
  [[ -f "$file" && -r "$file" ]] || return 1
  awk '
    BEGIN { fence = 0; insec = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (fence) {
        if (line ~ /^(```+|~~~+)$/ && length(line) >= delim_len && substr(line, 1, 1) == delim_ch) {
          fence = 0
        }
        next
      }
      if (match(line, /^(```+|~~~+)/)) {
        delim_ch = substr(line, 1, 1)
        delim_len = RLENGTH
        fence = 1
        next
      }
      if (insec) {
        if (match(line, /^#{1,2}[[:space:]]/)) exit
        print line
        next
      }
      if (line ~ /^##[[:space:]]+Gotchas([ \t]+#+)?[ \t]*$/) insec = 1
    }
  ' "$file"
}

trim_body() {
  # Drop leading and trailing blank lines; keep interior blanks.
  awk '
    { lines[NR] = $0 }
    END {
      start = 1
      while (start <= NR && lines[start] ~ /^[ \t]*$/) start++
      stop = NR
      while (stop >= start && lines[stop] ~ /^[ \t]*$/) stop--
      for (i = start; i <= stop; i++) print lines[i]
    }
  '
}

emit_layer() {
  local label="$1" file="$2" body
  body="$(extract_gotchas "$file" | trim_body)" || return 0
  [[ -n "$body" ]] || return 0
  if [[ "$emitted" -eq 0 ]]; then
    printf '### Consumer gotchas (cascade)\n\n'
  else
    printf '\n'
  fi
  printf '#### %s (`%s`)\n\n%s\n' "$label" "$file" "$body"
  emitted=1
}

emitted=0
root="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$root" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
fi

[[ -n "${HOME:-}" ]] && emit_layer "user-global" "$HOME/.claude/bugs.md"
[[ -n "$root" ]] && emit_layer "team" "$root/.claude/bugs.md"
[[ -n "$root" ]] && emit_layer "local overlay" "$root/.claude/bugs.local.md"

if [[ "$emitted" -eq 0 ]]; then
  printf '(none)\n'
fi
exit 0
