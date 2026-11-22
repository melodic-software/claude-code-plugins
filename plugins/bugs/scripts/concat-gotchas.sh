#!/usr/bin/env bash
# Always exits 0 so a skill pre-compute injection cannot fail skill load.
set -u

extract_gotchas() {
  local file="$1"
  [[ -f "$file" && -r "$file" ]] || return 1
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

emit_layer_or_old() {
  local label="$1" new="$2" old="$3" move="$4"
  read_file=""
  if readable "$new" && ! [[ "$old" -ef "$new" ]]; then
    read_file="$new"
    emit_layer "$label" "$new"
    readable "$old" && warnings+=("Warning: bugs no longer reads the gotchas in \`$old\`, because \`$new\` supplies the $label layer. Run \`/bugs:setup apply\` to $move, then delete the old file.")
  elif readable "$old"; then
    read_file="$old"
    emit_layer "$label (old path)" "$old"
    warnings+=("Warning: bugs read \`$old\`, an old config path. Run \`/bugs:setup apply\` to $move, then delete the old file.")
  fi
}

emitted=0
warnings=()
user_opt=""
[[ "${1:-}" == "--user-file" ]] && user_opt="${2:-}"
[[ "$user_opt" == \$\{user_config.* ]] && user_opt=""
root="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$root" ]] || root="$(git rev-parse --show-toplevel 2>/dev/null)"

# Config-cascade 1.3 special-root classification: a root that is $HOME or an
# ancestor of it, or is not inside a git working tree, has no team layer or personal override
# layer. Otherwise ~/.claude/bugs.md would be read again as the team layer.
if [[ -n "$root" && -n "${HOME:-}" ]]; then
  # Fold slashes, trailing slash, and case, as config-cascade step 2 and
  # source-control's root_is_home_or_ancestor do (Windows paths differ only so).
  rp="$(cd "$root" 2>/dev/null && pwd -P)" || rp="$root"
  hp="$(cd "$HOME" 2>/dev/null && pwd -P)" || hp="$HOME"
  rp="${rp//\\//}"; rp="${rp%/}"; rp="${rp,,}"
  hp="${hp//\\//}"; hp="${hp%/}"; hp="${hp,,}"
  [[ "$hp" == "$rp" || "$hp" == "$rp"/* ]] && root=""
fi
[[ -n "$root" && "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]] && root=""

old_user="${HOME:+$HOME/.claude/bugs.md}"
user_target="a file outside \`~/.claude\` that the bugs \`gotchas_file\` option names"
[[ -n "$user_opt" ]] && ! [[ "$user_opt" -ef "$old_user" ]] && user_target="\`$user_opt\`"
emit_layer_or_old "userConfig" "$user_opt" "$old_user" "move its \`## Gotchas\` to $user_target and any \`lanes\` or \`filing_posture\` to the homes \`/bugs:setup check\` names"
user="$read_file"
if [[ -n "$root" ]]; then
  team="$root/docs/conventions/bugs.md"
  [[ -n "$user" && "$team" -ef "$user" ]] || emit_layer "team" "$team"
  personal="$root/docs/conventions/bugs.local.md"
  old_personal="$root/.claude/bugs.local.md"
  [[ -n "$user" && "$personal" -ef "$user" ]] && personal=""
  [[ -n "$user" && "$old_personal" -ef "$user" ]] && old_personal=""
  emit_layer_or_old "personal override" "$personal" "$old_personal" "move what it holds into \`$root/docs/conventions/bugs.local.md\`"
fi

[[ "$emitted" -eq 0 ]] && printf '(none)\n'
for warning in ${warnings[@]+"${warnings[@]}"}; do
  printf '\n%s\n' "$warning"
done
exit 0
