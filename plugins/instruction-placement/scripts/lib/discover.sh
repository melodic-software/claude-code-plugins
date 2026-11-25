#!/usr/bin/env bash

ip_realpath() {
  local p="${1:-}" dir base target hops=0
  [[ -n "$p" ]] || return 0
  if [[ ! -e "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  if [[ -d "$p" ]]; then
    (cd -P "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"
    return 0
  fi

  dir="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)" || {
    printf '%s' "$p"
    return 0
  }
  base="$(basename "$p")"

  while [[ -L "$dir/$base" ]] && ((hops < 32)); do
    target="$(readlink "$dir/$base" 2>/dev/null)" || break
    [[ -n "$target" ]] || break
    case "$target" in
    /*)
      dir="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P)" || break
      ;;
    *)
      dir="$(cd -P "$dir/$(dirname "$target")" 2>/dev/null && pwd -P)" || break
      ;;
    esac
    base="$(basename "$target")"
    hops=$((hops + 1))
  done

  printf '%s/%s' "$dir" "$base"
}

ip_parse_paths() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 0
  awk '
    function emit(v,   a, b) {
      gsub(/^[[:space:]]+/, "", v); gsub(/[[:space:]]+$/, "", v)
      a = substr(v, 1, 1); b = substr(v, length(v), 1)
      if (length(v) > 1 && ((a == "\"" && b == "\"") || (a == "'"'"'" && b == "'"'"'")))
        v = substr(v, 2, length(v) - 2)
      if (v != "") print v
    }
    function emit_list(line,   part, depth, q, n, i, c) {
      part = ""; depth = 0; q = ""
      n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q != "") { if (c == q) q = ""; part = part c; continue }
        if ((c == "\"" || c == "'"'"'") && part ~ /^[[:space:]]*$/) { q = c; part = part c; continue }
        if (c == "{") depth++
        else if (c == "}") depth--
        else if (c == "," && depth == 0) { emit(part); part = ""; continue }
        part = part c
      }
      emit(part)
    }
    # A file whose first line is not `---` has no frontmatter, and the closing
    # `---` ends the parse, so every rule below runs inside the frontmatter.
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }

    /^paths:[[:space:]]*\[/ {
      line = $0
      sub(/^paths:[[:space:]]*\[/, "", line)
      # Drop the final `]` and anything after it. Using the LAST one keeps a
      # bracket expression inside a glob (`a[bc].ts`) intact.
      sub(/\][^]]*$/, "", line)
      emit_list(line)
      next
    }

    /^paths:[[:space:]]*$/ { inpaths = 1; next }

    # The string form. Its quotes wrap the whole list, so they come off before the
    # split. A value YAML would not read as a one-line string yields no pattern:
    # a block scalar marker, or an indicator such as the `*` of an unquoted
    # `**/*.ts`, which ip_frontmatter_problem reports as unparsable.
    /^paths:[[:space:]]*[^[:space:]]/ {
      line = $0
      sub(/^paths:[[:space:]]*/, "", line)
      c = substr(line, 1, 1)
      if (c == "\"" || c == "'"'"'") {
        end = index(substr(line, 2), c)
        if (end > 0) emit_list(substr(line, 2, end - 1))
        next
      }
      if (c ~ /[*@`|>&!%{#]/) next
      sub(/[[:space:]]+#.*$/, "", line)
      if (line ~ /^(~|null|Null|NULL|true|True|TRUE|false|False|FALSE)$/) next
      emit_list(line)
      next
    }
    inpaths && /^[[:space:]]+-[[:space:]]*/ {
      v = $0
      sub(/^[[:space:]]+-[[:space:]]*/, "", v)
      emit(v)
      next
    }
    inpaths && /^[^[:space:]]/ { inpaths = 0 }
  ' "$file" 2>/dev/null
}

# Unparsable rule frontmatter is ignored: the rule loads as if it had no paths.
# https://code.claude.com/docs/en/memory
ip_frontmatter_problem() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 0
  awk '
    function bad(reason) { printf "%d\t%s\n", NR, reason; exit }
    # Net flow-collection nesting of one line: openers minus closers.
    function nest(s,   t, o, c) {
      t = s; o = gsub(/[[{]/, "", t)
      t = s; c = gsub(/[]}]/, "", t)
      return o - c
    }
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    {
      if (open != "") {
        # Inside a quoted or flow value that began on an earlier line.
        if (open == "F") { depth += nest($0); if (depth <= 0) open = "" }
        else if (index($0, open) > 0) open = ""
        next
      }
      match($0, /^[[:space:]]*/); ind = RLENGTH
      if (block >= 0) {
        if (ind > block) next
        block = -1
      }
      if (substr($0, 1, ind) ~ /\t/) bad("tab in indentation")
      v = ""
      if (match($0, /^[[:space:]]*-[[:space:]]+/)) {
        v = substr($0, RLENGTH + 1)
        # `- key: value` opens a mapping item; judge only its value.
        if (match(v, /^[A-Za-z0-9_.-]+:([[:space:]]+|$)/)) v = substr(v, RLENGTH + 1)
      } else if (match($0, /^[[:space:]]*[A-Za-z0-9_.-]+:([[:space:]]+|$)/)) v = substr($0, RLENGTH + 1)
      else next
      sub(/[[:space:]]+$/, "", v)
      # An anchor or tag may precede the value: `&a |`, `!!str text`.
      while (match(v, /^[&!][^[:space:]]*[[:space:]]+/)) v = substr(v, RLENGTH + 1)
      if (v == "" || v ~ /^#/) next
      c = substr(v, 1, 1)
      if (c == "|" || c == ">") { block = ind; next }
      if (c == "\"" || c == "'"'"'") {
        if (index(substr(v, 2), c) == 0) open = c
        next
      }
      if (c == "[" || c == "{") {
        depth = nest(v)
        if (depth > 0) open = "F"
        next
      }
      # Only a plain value takes a trailing comment off here: in a quoted or flow
      # value a `#` can be text.
      sub(/[[:space:]]+#.*$/, "", v)
      if (c == "*") bad("plain value starts with * (a YAML alias); quote the glob")
      if (c == "@" || c == "`") bad("plain value starts with a reserved indicator " c "; quote it")
      if (v ~ /: / || v ~ /:$/) bad("plain value contains a colon followed by a space or at its end; quote it")
    }
    BEGIN { block = -1; open = ""; depth = 0 }
  ' "$file" 2>/dev/null
}

ip_discover_rules() {
  local root="${1:-.}"
  [[ -d "$root" ]] || return 0

  local rules_dir found_file real seen_file
  seen_file="$(mktemp)" || return 1

  while IFS= read -r rules_dir; do
    [[ -z "$rules_dir" ]] && continue
    while IFS= read -r found_file; do
      [[ -z "$found_file" ]] && continue
      real="$(ip_realpath "$found_file")"
      printf '%s\t%s\n' "$real" "${found_file#"$root"/}" >>"$seen_file"
    done < <(find -L "$rules_dir" -type f -name '*.md' 2>/dev/null)
  done < <(find -L "$root" -type d -name rules -path '*/.claude/rules' \
    -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

  LC_ALL=C sort "$seen_file" | awk -F'\t' -v fixture="$IP_FIXTURE_ERE" '
    $2 ~ fixture { next }
    {
      depth = gsub(/\//, "/", $2)
      if (!($1 in best) || depth < bestdepth[$1] ||
          (depth == bestdepth[$1] && $2 < best[$1])) {
        best[$1] = $2
        bestdepth[$1] = depth
      }
    }
    END { for (k in best) print best[k] }
  ' | LC_ALL=C sort

  rm -f "$seen_file"
}

IP_EXCLUDED_TREES=".claude node_modules vendor .git"
IP_FOREIGN_AGENT_TREES=".codex .cursor .github"

IP_FIXTURE_ERE='(^|/)(evals|tests)/fixtures/'

ip_discover_nested_instructions() {
  local root="${1:-.}"
  [[ -d "$root" ]] || return 0

  local listing
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    listing="$(git -C "$root" ls-files -z 2>/dev/null | tr '\0' '\n')"
  else
    listing="$(cd "$root" && find . -type f \
      \( -name 'CLAUDE.md' -o -name 'AGENTS.md' \) 2>/dev/null | sed 's|^\./||')"
  fi

  printf '%s\n' "$listing" |
    awk -v excluded="$IP_EXCLUDED_TREES" -v foreign="$IP_FOREIGN_AGENT_TREES" -v fixture="$IP_FIXTURE_ERE" '
    BEGIN {
      split(excluded, ex, " "); for (k in ex) skip[ex[k]] = 1
      split(foreign, others, " "); for (k in others) theirs[others[k]] = 1
    }
    $0 == "" { next }
    $0 ~ fixture { next }
    {
      n = split($0, seg, "/")
      if (n < 2) next                                   # root-level: loads at start
      base = seg[n]
      if (base != "CLAUDE.md" && base != "AGENTS.md") next
      for (i = 1; i < n; i++) {
        if (seg[i] in skip) next
        if (base == "AGENTS.md" && seg[i] in theirs) next
      }
      print
    }
  ' | LC_ALL=C sort
}

ip_entry_points_on_path() {
  local root="${1:-.}" dir="${2:-.}" base entry
  while :; do
    if [[ "$dir" == "." ]]; then base="$root"; else base="$root/$dir"; fi
    for entry in "$base/CLAUDE.md" "$base/.claude/CLAUDE.md" "$base/CLAUDE.local.md"; do
      [[ -f "$entry" ]] && printf '%s\n' "$entry"
    done
    [[ "$dir" == "." ]] && break
    dir="$(dirname "$dir")"
  done
}


# Claude Code's import parsing skips code spans and fenced code blocks.
# https://code.claude.com/docs/en/memory
_ip_imports_of() {
  local file="$1" dir
  dir="$(cd "$(dirname "$file")" && pwd)"
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)          # drop inline code spans
      gsub(/\\ /, "\001", line)          # an escaped space does not split the token
      n = split(line, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (substr(tok[i], 1, 1) == "@" && length(tok[i]) > 1) {
          t = substr(tok[i], 2)
          c = substr(t, 1, 1)
          if (c == "\"" || c == "'"'"'") continue
          sub(/[.,;:)]+$/, "", t)
          gsub(/\001/, " ", t)
          if (t != "") print t
        }
      }
    }
  ' "$file" 2>/dev/null | while IFS= read -r target; do
    case "$target" in
    /*) printf '%s\n' "$target" ;;
    "~"/*) printf '%s\n' "${HOME}/${target#\~/}" ;;
    *) printf '%s\n' "$dir/$target" ;;
    esac
  done
}

_ip_reaches() {
  local from="$1" want="$2" depth="${3:-0}"
  [[ -f "$from" ]] || return 1

  local resolved import_real
  resolved="$(ip_realpath "$from")"
  [[ "$resolved" == "$want" ]] && return 0
  ((depth >= 4)) && return 1

  local imported
  while IFS= read -r imported; do
    [[ -z "$imported" ]] && continue
    import_real="$(ip_realpath "$imported")"
    [[ "$import_real" == "$want" ]] && return 0
    if [[ -f "$import_real" ]] && _ip_reaches "$import_real" "$want" $((depth + 1)); then
      return 0
    fi
  done < <(_ip_imports_of "$from")
  return 1
}

ip_index_target_loaded() {
  local root="${1:-.}" target="${2:-}"
  [[ -n "$target" ]] || {
    printf 'UNREACHABLE\tno target given\n'
    return 1
  }

  local abs_target
  case "$target" in
  /*) abs_target="$(ip_realpath "$target")" ;;
  *) abs_target="$(ip_realpath "$root/$target")" ;;
  esac
  if [[ ! -f "$abs_target" ]]; then
    printf 'UNREACHABLE\t%s does not exist\n' "$target"
    return 1
  fi

  case "$target" in
  CLAUDE.md | CLAUDE.local.md | .claude/CLAUDE.md)
    printf 'LOADED\t%s is a root memory file, loaded at session start\n' "$target"
    return 0
    ;;
  *) ;;
  esac

  local target_dir="."
  [[ "$target" == /* ]] || target_dir="$(dirname "$target")"

  local entry blocker=""
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ -n "$blocker" ]] || blocker="${entry#"$root"/}"
    if _ip_reaches "$entry" "$abs_target" 0; then
      printf 'LOADED\t%s reaches %s\n' "${entry#"$root"/}" "$target"
      return 0
    fi
  done < <(ip_entry_points_on_path "$root" "$target_dir")

  if [[ -z "$blocker" && ("$target" == AGENTS.md || "$target" == */AGENTS.md) ]]; then
    printf 'NATIVE\t%s is not blocked: no CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md on its path, so Claude Code reads it directly where AGENTS.md support is available\n' \
      "$target"
    return 0
  fi

  printf 'UNREACHABLE\t%s is not imported by any memory file on its path%s\n' \
    "$target" \
    "${blocker:+, and $blocker is read instead of it}"
  return 1
}
