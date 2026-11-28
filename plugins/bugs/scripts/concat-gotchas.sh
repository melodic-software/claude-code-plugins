#!/usr/bin/env bash
set -u

extract_gotchas() {
  local file="$1"
  readable "$file" || return 1
  awk '
    {
      line = $0
      sub(/\r$/, "", line)
      if (fence || match(line, /^(```+|~~~+)/)) {
        if (!fence) {
          delim_ch = substr(line, 1, 1)
          delim_len = RLENGTH
          fence = 1
        } else if (line ~ /^(```+|~~~+)$/ && length(line) >= delim_len && substr(line, 1, 1) == delim_ch) {
          fence = 0
        }
        if (insec) print line
        next
      }
      if (insec) {
        # ##? not #{1,2}: mawk 1.3.3 matches ERE intervals as literal text.
        if (line ~ /^##?[[:space:]]/) exit
        print line
        next
      }
      if (line ~ /^##[[:space:]]+Gotchas([ \t]+#+)?[ \t]*$/) insec = 1
    }
  ' "$file"
}

trim_body() {
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
  body="$(extract_gotchas "$file" | trim_body)"
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

readable() { [[ -n "$1" && -f "$1" && -r "$1" ]]; }

emitted=0
user_opt=""
[[ "${1:-}" == "--user-file" ]] && user_opt="${2:-}"
[[ "$user_opt" == \$\{user_config.* ]] && user_opt=""
root="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$root" ]] || root="$(git rev-parse --show-toplevel 2>/dev/null)"

if [[ -n "$root" && -n "${HOME:-}" ]]; then
  rp="$(cd "$root" 2>/dev/null && pwd -P)" || rp="$root"
  hp="$(cd "$HOME" 2>/dev/null && pwd -P)" || hp="$HOME"
  rp="${rp//\\//}"; rp="${rp%/}"; rp="${rp,,}"
  hp="${hp//\\//}"; hp="${hp%/}"; hp="${hp,,}"
  [[ "$hp" == "$rp" || "$hp" == "$rp"/* ]] && root=""
fi
[[ -n "$root" && "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]] && root=""

user=""
if readable "$user_opt"; then
  user="$user_opt"
  emit_layer "userConfig" "$user"
fi
if [[ -n "$root" ]]; then
  team="$root/docs/conventions/bugs.md"
  [[ -n "$user" && "$team" -ef "$user" ]] || emit_layer "team" "$team"
  personal="$root/docs/conventions/bugs.local.md"
  [[ -n "$user" && "$personal" -ef "$user" ]] || emit_layer "personal override" "$personal"
fi

[[ "$emitted" -eq 0 ]] && printf '(none)\n'
exit 0
