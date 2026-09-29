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
        if (insec) print line
        next
      }
      if (match(line, /^(```+|~~~+)/)) {
        delim_ch = substr(line, 1, 1)
        delim_len = RLENGTH
        fence = 1
        if (insec) print line
        next
      }
      if (insec) {
        # ##? not #{1,2}: mawk 1.3.3 matches ERE intervals as literal text.
        if (match(line, /^##?[[:space:]]/)) exit
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
  # shellcheck disable=SC2016  # backticks are the literal markdown code span in the printf format, not substitution
  printf '#### %s (`%s`)\n\n%s\n' "$label" "$file" "$body"
  emitted=1
}

emitted=0
root="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$root" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
fi

# Config-cascade 1.3 special-root classification: a root that is $HOME or an
# ancestor of it, or is not inside a git working tree, has no team or overlay
# layer. Otherwise ~/.claude/bugs.md would be read again as the team layer.
if [[ -n "$root" && -n "${HOME:-}" ]]; then
  rp="$(cd "$root" 2>/dev/null && pwd -P)" || rp="$root"
  hp="$(cd "$HOME" 2>/dev/null && pwd -P)" || hp="$HOME"
  [[ "$hp" == "$rp" || "$hp" == "${rp%/}"/* ]] && root=""
fi
if [[ -n "$root" && "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]; then
  root=""
fi

user="${HOME:+$HOME/.claude/bugs.md}"
[[ -n "$user" ]] && emit_layer "user-global" "$user"
for pair in "team:bugs.md" "local overlay:bugs.local.md"; do
  [[ -n "$root" ]] || break
  file="$root/.claude/${pair#*:}"
  [[ -n "$user" && "$file" -ef "$user" ]] && continue
  emit_layer "${pair%%:*}" "$file"
done

if [[ "$emitted" -eq 0 ]]; then
  printf '(none)\n'
fi
exit 0
