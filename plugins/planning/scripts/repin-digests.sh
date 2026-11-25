#!/usr/bin/env bash
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

inside_root() {
  local dir
  [[ -f "$1" && ! -L "$1" ]] || return 1
  dir="$(cd "$(dirname "$1")" && pwd -P)" || return 1
  [[ "$dir/" == "$root/"* ]] || return 1
  inside_path="$dir/$(basename "$1")"
}

arg_re='^[[:space:]]+"(.*)"[[:space:]]*\\$'
label_re='^pin_[a-z_]* "(.*)"[[:space:]]*$'
kind_re='^(pin_[a-z_]*) .*$'
olds=()
news=()
pin_labels=()
unchanged=0
for i in "${!call_lines[@]}"; do
  call="${call_lines[$i]}"
  old="$(sed -n "${sha_lines[$i]}p" "$test_file" | tr -d ' \t"')"
  call_text="$(sed -n "${call}p" "$test_file")"
  pin_label="${call_text//\\/}"
  [[ "$pin_label" =~ $label_re ]] && pin_label="${BASH_REMATCH[1]}"
  kind="$call_text"
  [[ "$call_text" =~ $kind_re ]] && kind="${BASH_REMATCH[1]}"
  olds+=("$old")
  pin_labels+=("$pin_label")
  news+=("")

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
cat "$tmp" >"$test_file" || exit 2

for i in "${!pin_labels[@]}"; do
  echo "${pin_labels[$i]}: ${olds[$i]} -> ${news[$i]}"
done
