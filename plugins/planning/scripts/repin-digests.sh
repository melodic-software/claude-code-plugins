#!/usr/bin/env bash
# Re-pin one or more digest pins of interview-defenses.test.sh from the files alone.
#
#   repin-digests.sh [--test-file <path>] <pin-label>... <justification>
#
# The last argument is the justification; every argument before it is a pin label, so one
# call re-pins several pins under one reason. Run it after reading the diff of the guarded
# text and confirming the defense still holds; the commit carries the printed old -> new
# lines and the reason, and the PR review judges the change.
#
# It runs nothing from the test file's checkout: it reads the test file as text and computes
# each digest with lib/pin-digests.sh from its own directory, so the issue lane can run it
# from a read-only base copy against the checkout it is changing. The PR's CI runs the test;
# tests/repin.sh calls this script and then runs the test itself. It
#   1. finds, for each label, the one digest pin (pin_section, pin_frontmatter,
#      pin_case_digest, pin_case_set or pin_file) whose call line contains it (backslashes
#      ignored, so a label with backticks is typed plainly), resolving every label before
#      it writes anything,
#   2. reads each pin's arguments as plain double-quoted strings: `$PLUGIN_DIR` is the
#      directory above the test file's own, and any other `$NAME` or `${NAME}` is the value of
#      the test file's one column-0 `NAME="..."` line, read the same way but with no variable
#      other than `$PLUGIN_DIR`; any other `$`, an unescaped backtick or quote, or a file
#      outside that directory refuses the pin,
#   3. rewrites only those pins' sha256 literals to the computed digests and inserts
#      `# <justification>` on the line above each call, beside the existing re-pin comments,
#   4. prints `<label>: <old> -> <new>` per pin, in the order named, for the commit message.
# Every other line of the file stays byte-identical.
#
# The test file defaults to plugins/planning/tests/interview-defenses.test.sh under the
# current directory, the checkout, never the copy beside this script. The plugin directory,
# symbolic links resolved, must be the current directory or sit under it, so no pin reads a
# file outside the checkout the script runs in.
#
# Exit: 0 re-pinned; 2 usage, an unreadable test file or one whose plugin directory is not
# under the current directory, or no digest tool or jq;
# 3 a label matches no digest pin, or more than one, or names the same pin as an earlier
# label; 4 nothing changed: a named pin's digest already matches, its arguments are not plain
# data, it reads a file outside the plugin, or it fails for a reason a new digest does not fix
# (such as a section boundary that is no longer a unique heading line). On 2, 3 and 4 the
# file is unchanged.
set -uo pipefail

self="$(basename "$0")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/pin-digests.sh
source "$here/lib/pin-digests.sh" || exit 2
test_file="plugins/planning/tests/interview-defenses.test.sh"

usage() {
  echo "usage: $self [--test-file <path>] <pin-label>... <justification>" >&2
  exit 2
}

if [[ "${1:-}" == "--test-file" ]]; then
  [[ $# -ge 2 ]] || usage
  test_file="$2"
  shift 2
fi
[[ $# -ge 2 ]] || usage
labels=("${@:1:$#-1}")
justification="${!#}"
for label in "${labels[@]}"; do
  [[ -n "$label" ]] || usage
done
if [[ -z "${justification//[[:space:]]/}" || "$justification" == *$'\n'* ]]; then
  echo "$self: the justification must be one non-empty line." >&2
  exit 2
fi
[[ -f "$test_file" && ! -L "$test_file" ]] || {
  echo "$self: no test file (a regular file, not a link) at $test_file" >&2
  exit 2
}
root="$(cd "$(dirname "$test_file")/.." && pwd -P)" || exit 2
cwd="$(pwd -P)" || exit 2
if [[ "$root" != "$cwd" && "$root/" != "$cwd/"* ]]; then
  echo "$self: the test file's plugin directory $root is not under the current directory $cwd." >&2
  exit 2
fi

# Locate a pin: "<call line>\t<sha line>" for every digest-pin call whose first line
# holds the label. The sha literal is the call's last argument, alone on its own line.
# The label rides in the environment, not -v: awk would process backslash escapes in a -v value.
find_pins() {
  REPIN_LABEL="$1" awk '
    # A quoted 64-hex literal is 66 characters; no {64} interval, which mawk may lack.
    function sha_len(s) { gsub(/[[:space:]]/, "", s); return length(s) }
    BEGIN { want = ENVIRON["REPIN_LABEL"] }
    /^pin_(section|frontmatter|case_digest|case_set|file) / {
      call = NR
      line = $0
      gsub(/\\/, "", line)
      hit = (index(line, want) > 0)
      next
    }
    call && /^[[:space:]]*"[0-9a-f]+"[[:space:]]*$/ && sha_len($0) == 66 {
      if (hit) print call "\t" NR
      call = 0
      next
    }
    call && /^[^[:space:]]/ { call = 0 }
  ' "$test_file"
}

# Resolve every label before any write, reporting each one that does not name exactly one
# new pin.
call_lines=()
sha_lines=()
refused=0
for label in "${labels[@]}"; do
  matches="$(find_pins "$label")"
  count=0
  [[ -n "$matches" ]] && count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  if [[ "$count" -ne 1 ]]; then
    echo "$self: \"$label\" matches $count digest pins in ${test_file}; name exactly one." >&2
    refused=1
    continue
  fi
  call_line="${matches%%$'\t'*}"
  for seen in ${call_lines[@]+"${call_lines[@]}"}; do
    if [[ "$seen" == "$call_line" ]]; then
      echo "$self: \"$label\" names the same digest pin as an earlier label; name each pin once." >&2
      refused=1
      continue 2
    fi
  done
  call_lines+=("$call_line")
  sha_lines+=("${matches##*$'\t'}")
done
[[ $refused -eq 0 ]] || exit 3

# var_raw <name>: the text inside the quotes of the test file's one column-0 NAME="..." line.
var_raw() {
  local name="$1" line raw="" n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$name="* ]] || continue
    n=$((n + 1))
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*=\"(.*)\"$ ]] || return 1
    raw="${BASH_REMATCH[1]}"
  done <"$test_file"
  [[ $n -eq 1 ]] || return 1
  printf '%s' "$raw"
}

# var_value <name> <depth>: sets var_out to a variable's value, read as data, never
# evaluated. At depth 0 (a pin argument) any variable resolves; at depth 1 (a variable's own
# value) only $PLUGIN_DIR does, so no chain of variables can multiply the reads. Each value is
# read once and kept.
var_names=()
var_values=()
var_value() {
  local raw k
  if [[ "$1" == PLUGIN_DIR ]]; then
    var_out="$root"
    return 0
  fi
  [[ "$2" -eq 0 ]] || return 1
  for ((k = 0; k < ${#var_names[@]}; k++)); do
    if [[ "${var_names[k]}" == "$1" ]]; then
      var_out="${var_values[k]}"
      return 0
    fi
  done
  raw="$(var_raw "$1")" || return 1
  dq_value "$raw" 1 || return 1
  var_names+=("$1")
  var_values+=("$dq_out")
  var_out="$dq_out"
}

# dq_value <text> <depth>: sets dq_out to the value bash gives the inside of a double-quoted
# string, for the plain subset: backslash escapes and $NAME or ${NAME}. Anything else (a
# command or arithmetic substitution, a backtick, a parameter operator, an unescaped quote)
# is status 1.
dq_value() {
  local raw="$1" depth="$2" out="" i=0 c next
  while [[ $i -lt ${#raw} ]]; do
    c="${raw:i:1}"
    case "$c" in
      \\)
        next="${raw:i+1:1}"
        case "$next" in
          '') return 1 ;;
          '$' | '`' | '"' | \\) out+="$next" ;;
          *) out+="$c$next" ;;
        esac
        i=$((i + 2))
        ;;
      '$')
        if [[ "${raw:i}" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\} || "${raw:i}" =~ ^\$([A-Za-z_][A-Za-z0-9_]*) ]]; then
          i=$((i + ${#BASH_REMATCH[0]}))
          var_value "${BASH_REMATCH[1]}" "$depth" || return 1
          out+="$var_out"
        else
          return 1
        fi
        ;;
      '`' | '"') return 1 ;;
      *)
        out+="$c"
        i=$((i + 1))
        ;;
    esac
  done
  dq_out="$out"
}

# inside_root <path>: a regular file, not a link, under the plugin directory. Sets
# inside_path to its absolute path, which every read below uses.
inside_root() {
  local dir
  [[ -f "$1" && ! -L "$1" ]] || return 1
  dir="$(cd "$(dirname "$1")" && pwd -P)" || return 1
  [[ "$dir/" == "$root/"* ]] || return 1
  inside_path="$dir/$(basename "$1")"
}

arg_re='^[[:space:]]+"(.*)"[[:space:]]*\\$'
olds=()
news=()
pin_labels=()
unchanged=0
for i in "${!call_lines[@]}"; do
  call="${call_lines[$i]}"
  old="$(sed -n "${sha_lines[$i]}p" "$test_file" | tr -d ' \t"')"
  # The label is the call's first argument, backslashes dropped; it ends at the line's last quote.
  pin_label="$(sed -n "${call}p" "$test_file" | tr -d "\\\\" | sed 's/^pin_[a-z_]* "\(.*\)"[[:space:]]*$/\1/')"
  kind="$(sed -n "${call}p" "$test_file" | sed 's/^\(pin_[a-z_]*\) .*/\1/')"
  olds+=("$old")
  pin_labels+=("$pin_label")
  news+=("")

  # Every line between the call line and the sha literal is one plain quoted argument.
  args=()
  why=""
  for ((n = call + 1; n < sha_lines[i]; n++)); do
    line="$(sed -n "${n}p" "$test_file")"
    if [[ "$line" =~ $arg_re ]] && dq_value "${BASH_REMATCH[1]}" 0; then
      args+=("$dq_out")
    else
      why="argument line $n is not a plain quoted string"
      break
    fi
  done
  if [[ -z "$why" ]]; then
    case "$kind:${#args[@]}" in
      pin_section:3 | pin_frontmatter:1 | pin_file:1)
        if inside_root "${args[0]}"; then
          target="$inside_path"
        else
          why="it reads ${args[0]}, which is not a file under $root"
        fi
        ;;
      pin_case_digest:1 | pin_case_set:0)
        if ! command -v jq >/dev/null 2>&1; then
          echo "$self: jq is required to digest an eval case." >&2
          exit 2
        fi
        if ! var_value EVALS 0 || ! inside_root "$var_out"; then
          why="its EVALS file is not a plain path to a file under $root"
        elif ! jq -e . "$inside_path" >/dev/null 2>&1; then
          why="$inside_path is not parsable JSON"
        elif [[ "$kind" == pin_case_digest &&
          "$(jq --arg n "${args[0]}" '[.evals[] | select(.name == $n)] | length' "$inside_path" 2>/dev/null)" != 1 ]]; then
          why="no one eval case is named ${args[0]}"
        fi
        evals="$inside_path"
        ;;
      *) why="$kind takes a different number of arguments than ${#args[@]}" ;;
    esac
  fi
  if [[ -z "$why" && "$kind" == pin_section ]]; then
    if [[ "$(grep -Fxc -- "${args[1]}" "$target")" != 1 || "$(grep -Fxc -- "${args[2]}" "$target")" != 1 ]]; then
      why="its section boundaries are no longer unique whole lines"
    fi
  fi
  if [[ -n "$why" ]]; then
    echo "$self: nothing to change for ${pin_label}: $why." >&2
    unchanged=1
    continue
  fi

  case "$kind" in
    pin_section) new="$(section_digest "$target" "${args[1]}" "${args[2]}")" ;;
    pin_frontmatter) new="$(frontmatter_digest "$target")" ;;
    pin_file) new="$(file_digest "$target")" ;;
    pin_case_digest) new="$(case_digest "$evals" "${args[0]}")" ;;
    pin_case_set) new="$(case_set_digest "$evals")" ;;
    *) exit 2 ;;
  esac
  if [[ ! "$new" =~ ^[0-9a-f]{64}$ ]]; then
    echo "$self: no sha256 digest for ${pin_label} (is sha256sum or shasum installed?)." >&2
    exit 2
  fi
  if [[ "$new" == "$old" ]]; then
    echo "$self: nothing to change for ${pin_label}: the digest already matches." >&2
    unchanged=1
    continue
  fi
  news[i]="$new"
done
[[ $unchanged -eq 0 ]] || exit 4

tmp="$(mktemp "${TMPDIR:-/tmp}/repin.XXXXXX")" || exit 2
trap 'rm -f "$tmp"' EXIT
REPIN_NOTE="$justification" awk -v calls="${call_lines[*]}" -v shas="${sha_lines[*]}" -v news="${news[*]}" '
  BEGIN {
    note = ENVIRON["REPIN_NOTE"]
    n = split(calls, c, " ")
    split(shas, s, " ")
    split(news, d, " ")
    for (i = 1; i <= n; i++) { is_call[c[i]] = 1; new_at[s[i]] = d[i] }
  }
  NR in is_call { print "# " note }
  NR in new_at { sub(/[0-9a-f]+/, new_at[NR]) }
  { print }
' "$test_file" >"$tmp" || exit 2
# Write through the existing file so its mode and ownership stay.
cat "$tmp" >"$test_file" || exit 2

for i in "${!pin_labels[@]}"; do
  echo "${pin_labels[$i]}: ${olds[$i]} -> ${news[$i]}"
done
