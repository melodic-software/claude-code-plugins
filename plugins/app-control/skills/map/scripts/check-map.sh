#!/usr/bin/env bash
# Structural check of one control skill against plugins/app-control/reference/control-skill.md.
# Prints one finding per line as `<rule> | <path> | <detail>`, paths relative to the control
# skill directory. Never edits. Exits 0 with or without findings; 2 on a usage error.
#
# Rules:
#   index-form         an index line names no feature file in its second field
#   index-dead         an index line names a feature file that does not exist
#   index-duplicate    two index lines name the same feature file
#   index-missing      a feature file on disk has no index line
#   index-entry-count  an index line's `entry points: <n>` differs from the file's entry lines
#   index-glob         an index source glob matches no file under the project root (the
#                      directory holding .claude/), or is absolute, has a `..` segment, or
#                      starts in a symlink that leads outside that root
#   section-missing    a feature README lacks one of the six sections
#   section-extra      a feature README has an H2 section outside the six
#   section-order      a feature README's sections are out of the contract's order
#   entry-marker       an entry point line ends with neither `driven` nor `not driven: <reason>`
#   entry-reason       an entry point line ends `not driven` with no reason
#   link               a relative Markdown link in any .md file resolves to nothing
#   shared-use         a `shared/<item>` is named by fewer than two feature files
#   shared-why         a `shared/<item>` has no `Why shared: <reason>` line (in its README.md
#                      for a folder, in the file for a file, after an optional comment marker)
#   size-budget        the hub, a feature README.md at any depth or a legacy features/<f>.md has
#                      more characters than its budget in the contract's "Size budget" section
#   ready-listing      a command under the hub's `## Ready` (a fenced line, a code span, or a plain
#                      line with no code span) ends in a container or resource listing, which exits
#                      0 with no rows; the contract's "The Ready command" says to end it in grep -q.
#                      A kubectl get that names an object exits 1 when it is missing: not a listing
#   mask-missing       the hub's `## Capture` names `screenshot` or `video` on a row whose tool is
#                      not `none`, and its `## Mask` holds no unfenced `- <label> | <regex>` line
#                      and no `none: <reason>` line
#
# A legacy `features/<f>.md` gets the index and link rules only: the contract keeps it working as
# written. A README.md inside a feature's folder belongs to that feature, not to a new one. Hidden
# files and dependency folders (node_modules, .venv) are skipped. What a shared item is, what counts as a use and where its why line goes: the contract's
# "Shared items" section.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-map.sh <control-skill-dir> [--root <repository-root>]

Checks a control skill's structure and prints `<rule> | <path> | <detail>` per finding.
--root   where index source globs resolve (default: the project holding .claude/, for a
         <project>/.claude/skills/<name> directory; else the git top level)
EOF
}

dir="" root=""
while (($#)); do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    [[ $# -ge 2 ]] || {
      echo "check-map.sh: --root needs a value" >&2
      exit 2
    }
    root="$2"
    shift 2
    ;;
  -*)
    echo "check-map.sh: unknown argument: $1" >&2
    exit 2
    ;;
  *)
    [[ -z "$dir" ]] || {
      echo "check-map.sh: one control skill directory only" >&2
      exit 2
    }
    dir="$1"
    shift
    ;;
  esac
done

[[ -n "$dir" ]] || {
  usage >&2
  exit 2
}
[[ -d "$dir" ]] || {
  echo "check-map.sh: not a directory: $dir" >&2
  exit 2
}
[[ -f "$dir/SKILL.md" ]] || {
  echo "check-map.sh: no SKILL.md in $dir" >&2
  exit 2
}
dir="$(cd "$dir" && pwd)"
if [[ -z "$root" ]]; then
  if [[ "$(basename "$(dirname "$(dirname "$dir")")")" == .claude ]]; then
    root="$(cd "$dir/../../.." && pwd)"
  elif ! root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "check-map.sh: $dir is not under .claude/skills/ or in a git repository; pass --root" >&2
    exit 2
  fi
fi
[[ -d "$root" ]] || {
  echo "check-map.sh: not a directory: $root" >&2
  exit 2
}

root_real="$(cd "$root" && pwd -P)"
SECTIONS=("Parts" "Sub-features" "Entry points" "Reset" "Drive" "Gotchas")

finding() { printf '%s | %s | %s\n' "$1" "$2" "$3"; }
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}
# Lines of a Markdown file outside fenced code blocks.
unfenced() { awk '/^[[:space:]]*(```|~~~)/ { fence = !fence; next } !fence' "$1"; }
# H2 headings of a file, in order.
h2s() { unfenced "$1" | sed -n 's/^## \(.*[^[:space:]]\)[[:space:]]*$/\1/p'; }
# Non-blank lines under `## Entry points`.
entry_lines() {
  unfenced "$1" | awk '/^## / { inside = ($0 ~ /^## Entry points[[:space:]]*$/); next } inside && NF'
}

declare -A features=() indexed=()
while IFS= read -r f; do features["$f"]=readme; done < <(cd "$dir" && find features -mindepth 2 -type f -name README.md 2>/dev/null | LC_ALL=C sort)
# Drop a README.md that sits inside another feature's folder.
for f in "${!features[@]}"; do
  d="$(dirname "$(dirname "$f")")"
  while [[ "$d" == features/* ]]; do
    key="$d/README.md"
    [[ -z "${features[$key]:-}" ]] || {
      unset 'features[$f]'
      break
    }
    d="$(dirname "$d")"
  done
done
while IFS= read -r f; do features["$f"]=legacy; done < <(cd "$dir" && find features -mindepth 1 -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)

# Index lines, in hub order: a bullet with a field that names a feature file or an entry count.
while IFS= read -r line; do
  IFS='|' read -r -a fields <<<"$line"
  path="$(trim "${fields[1]:-}")"
  if [[ "$path" != features/?* ]]; then
    finding index-form SKILL.md "$line"
    continue
  fi
  if [[ -n "${indexed[$path]:-}" ]]; then
    finding index-duplicate SKILL.md "$path is indexed more than once"
    continue
  fi
  indexed["$path"]=1
  if [[ ! -f "$dir/$path" ]]; then
    finding index-dead SKILL.md "$path does not exist"
  elif [[ "${features[$path]:-}" == readme ]]; then
    count="$(trim "${fields[2]:-}")"
    count="${count#entry points:}"
    count="$(trim "$count")"
    actual="$(entry_lines "$dir/$path" | wc -l | tr -d ' ')"
    [[ "$count" == "$actual" ]] || finding index-entry-count SKILL.md "$path: index says $count, the file has $actual"
  fi
  sources="$(trim "${fields[3]:-}")"
  sources="${sources#sources:}"
  IFS=',' read -r -a globs <<<"$sources"
  for glob in "${globs[@]}"; do
    glob="$(trim "$glob")"
    [[ -n "$glob" ]] || continue
    # The literal part before the first wildcard must resolve inside the root, so a symlink
    # cannot carry the expansion out of the project.
    # A directory that does not exist expands to nothing, so it stays with the root.
    prefix="${glob%%[*?[]*}"
    [[ "$prefix" == */ ]] || prefix="$(dirname "$prefix")"
    real="$(cd "$root/$prefix" 2>/dev/null && pwd -P)" || real="$root_real"
    if [[ "$glob" == /* || "/$glob/" == */../* || ("$real" != "$root_real" && "$real" != "$root_real"/*) ]]; then
      finding index-glob SKILL.md "$path: $glob leaves the project root"
      continue
    fi
    hits="$(
      cd "$root"
      shopt -s globstar nullglob
      IFS=''
      # shellcheck disable=SC2206 # the glob is meant to expand; IFS='' stops word splitting
      matches=($glob)
      # A pattern with no glob characters comes back as itself, so count only what exists.
      n=0
      for m in "${matches[@]}"; do [[ -e "$m" ]] && n=$((n + 1)); done
      printf '%s' "$n"
    )"
    [[ "$hits" != 0 ]] || finding index-glob SKILL.md "$path: $glob matches no file"
  done
done < <(unfenced "$dir/SKILL.md" | { grep -E '^- .*\|[[:space:]]*(features/|entry points:)' || true; })

mapfile -t feature_list < <(printf '%s\n' "${!features[@]}" | LC_ALL=C sort)
for f in "${feature_list[@]}"; do
  [[ -n "$f" ]] || continue
  [[ -n "${indexed[$f]:-}" ]] || finding index-missing "$f" "no index line names this feature file"
  [[ "${features[$f]}" == readme ]] || continue

  mapfile -t have < <(h2s "$dir/$f")
  declare -A seen=()
  present=()
  for h in "${have[@]}"; do
    seen["$h"]=1
    is_known=0
    for s in "${SECTIONS[@]}"; do [[ "$h" == "$s" ]] && is_known=1; done
    if ((is_known)); then present+=("$h"); else finding section-extra "$f" "## $h"; fi
  done
  want=()
  for s in "${SECTIONS[@]}"; do
    if [[ -n "${seen[$s]:-}" ]]; then want+=("$s"); else finding section-missing "$f" "## $s"; fi
  done
  [[ "${present[*]}" == "${want[*]}" ]] || finding section-order "$f" "$(
    IFS=,
    printf '%s' "${present[*]}"
  )"
  unset seen

  while IFS= read -r entry; do
    e="$(trim "$entry")"
    if [[ "$e" =~ not\ driven:[[:space:]]*[^[:space:]] ]]; then
      :
    elif [[ "$e" =~ not\ driven:?$ ]]; then
      finding entry-reason "$f" "$e"
    elif [[ "$e" =~ (^|[^[:alnum:]_-])driven$ ]]; then
      :
    else
      finding entry-marker "$f" "$e"
    fi
  done < <(entry_lines "$dir/$f")
done

# Relative links in every Markdown file of the control skill.
# shellcheck disable=SC2016 # the backticks are the Markdown code-span delimiter, not a substitution
link_targets() { unfenced "$1" | sed 's/`[^`]*`//g' | { grep -oE '\]\([^)]+\)' || true; } | sed 's/^](//; s/)$//'; }
while IFS= read -r md; do
  base="$(dirname "$dir/$md")"
  while IFS= read -r target; do
    target="${target%% *}"
    target="${target#<}"
    target="${target%>}"
    target="${target%%#*}"
    [[ -n "$target" ]] || continue
    [[ "$target" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]] && continue
    [[ -e "$base/$target" ]] || finding link "$md" "$target does not resolve"
  done < <(link_targets "$dir/$md")
done < <(cd "$dir" && find . \( -name node_modules -o -name '.?*' \) -prune -o -type f -name '*.md' -print | sed 's|^\./||' | LC_ALL=C sort)

# shared/ items.
if [[ -d "$dir/shared" ]]; then
  while IFS= read -r item; do
    name="${item#shared/}"
    # shellcheck disable=SC2016 # $ is a regex character to escape, not an expansion
    escaped="$(printf '%s' "$name" | sed 's/[][\.*^$()+?{}|]/\\&/g')"
    users=0
    for f in "${feature_list[@]}"; do
      [[ -n "$f" ]] || continue
      if grep -qE "shared/$escaped([^A-Za-z0-9._-]|\$)" "$dir/$f"; then users=$((users + 1)); fi
    done
    ((users >= 2)) || finding shared-use "$item" "named by $users feature file(s); shared/ holds only what two or more use"
    readme="$dir/$item"
    [[ -d "$readme" ]] && readme="$readme/README.md"
    if [[ ! -f "$readme" ]]; then
      finding shared-why "$item" "no README.md"
    elif ! grep -qiE '^[[:space:]]*(#|//|--|<!--)?[[:space:]]*why shared:[[:space:]]*[^[:space:]]' "$readme"; then
      finding shared-why "$item" "no 'Why shared: <reason>' line"
    fi
  done < <(cd "$dir" && find shared -mindepth 1 -maxdepth 1 -not -name '.*' | LC_ALL=C sort)
fi

# Size budget, in UTF-8 characters, newlines included. Every byte that is not a continuation byte
# (0x80-0xBF) starts one character, so the count needs no UTF-8 locale on the host.
HUB_BUDGET=16000 FEATURE_BUDGET=4000
over_budget() { # <path relative to the control skill> <budget>
  local chars
  chars="$(LC_ALL=C tr -d '\200-\277' <"$dir/$1" | wc -c | tr -d ' ')"
  ((chars <= $2)) || finding size-budget "$1" "$chars characters, budget $2"
}
over_budget SKILL.md "$HUB_BUDGET"
while IFS= read -r md; do over_budget "$md" "$FEATURE_BUDGET"; done < <(
  cd "$dir" && {
    find features -mindepth 1 -maxdepth 1 -type f -name '*.md'
    find features \( -name node_modules -o -name '.?*' \) -prune -o -type f -path 'features/*/*' -name README.md -print
  } 2>/dev/null | LC_ALL=C sort
)

# Ready commands: fenced lines, code spans, and plain lines with no code span, under the hub's
# `## Ready`.
# shellcheck disable=SC2016 # the backticks are the Markdown code-span delimiter, not a substitution
ready_commands() {
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    !fence && /^## / { inside = ($0 ~ /^## Ready[[:space:]]*$/); next }
    !inside || !NF { next }
    fence || index($0, "`") == 0 { print; next }
    {
      line = $0
      while (match(line, /`[^`]+`/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1"
}
LISTING_RE='^((docker|podman|nerdctl)[[:space:]]+(ps|container[[:space:]]+(ls|list|ps)|compose[[:space:]]+ps)|docker-compose[[:space:]]+ps|kubectl[[:space:]]+get|systemctl[[:space:]]+list-units)([[:space:]]|$)'
# A `kubectl get` that names an object (`deploy/shop`, `pod shop-db-0`, `-f shop.yaml`) exits 1 when
# the object is missing, so only a get of resource types alone is a listing. A flag below takes the
# next word as its value, so that word is not a resource type. The answer is set in `named` (1 or
# 0) rather than returned, so the call needs no condition that would turn errexit off inside it.
KUBECTL_VALUE_FLAGS=' -n -l -o -L -s -v --namespace --selector --output --field-selector --label-columns
  --sort-by --context --kubeconfig --cluster --user --server --template --chunk-size --request-timeout
  --as --as-group --as-uid --token --cache-dir --certificate-authority --client-certificate --client-key
  --tls-server-name --username --password --subresource --profile --profile-output --v '
kubectl_names_object() { # <last stage>
  local -a words
  local w types=0 skip=0
  named=1
  read -r -a words <<<"$1"
  for w in "${words[@]:2}"; do
    if ((skip)); then
      skip=0
      continue
    fi
    case "$w" in
    -f | -k | --filename | --filename=* | --kustomize | --kustomize=* | --raw | --raw=*) return 0 ;;
    -*) [[ "$KUBECTL_VALUE_FLAGS" == *[[:space:]]"$w"[[:space:]]* ]] && skip=1 ;;
    */*) return 0 ;;
    *) types=$((types + 1)) ;;
    esac
  done
  named=$((types > 1))
}
while IFS= read -r cmd; do
  # Empty quoted text, so a `|` inside a --format string is not a stage, then keep the last stage.
  # The empty quotes stay as a word, so a flag's quoted value is still one word.
  last="$(printf '%s\n' "$cmd" | sed -E "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g; s/.*(&&|\|\||;|\|)//")"
  last="$(trim "$last")"
  [[ "$last" =~ $LISTING_RE ]] || continue
  if [[ "$last" == kubectl* ]]; then
    kubectl_names_object "$last"
    if ((named)); then continue; fi
  fi
  finding ready-listing SKILL.md "$(trim "$cmd"): ends in a listing, which exits 0 with no rows; end it in grep -q on the expected row"
done < <(ready_commands "$dir/SKILL.md")

# Lines under the hub's `## <heading>`, fence markers left out; fenced lines only with `fenced`.
section_lines() { # <file> <heading> [fenced]
  awk -v h="## $2" -v keep="${3:-}" '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    !fence && /^## / { sub(/[[:space:]]+$/, ""); inside = ($0 == h); next }
    inside && (!fence || keep == "fenced")' "$1"
}
# A row whose tool is `none` (`- trace, video: none`, `| video | none |`) records nothing.
image_kinds="$(section_lines "$dir/SKILL.md" Capture fenced |
  { grep -viE '(:|\|)[[:space:]]*none[[:space:]]*\|?[[:space:]]*$' || true; } |
  { grep -oiwE 'screenshots?|videos?' || true; } |
  tr '[:upper:]' '[:lower:]' | sed 's/s$//' | LC_ALL=C sort -u | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
if [[ -n "$image_kinds" ]]; then
  mask_lines="$(section_lines "$dir/SKILL.md" Mask |
    { grep -cE '^[[:space:]]*(-[[:space:]]+[^|]*[^|[:space:]][^|]*\|[[:space:]]*[^[:space:]]|none:[[:space:]]*[^[:space:]])' || true; })"
  [[ "$mask_lines" != 0 ]] || finding mask-missing SKILL.md "## Capture records $image_kinds with no ## Mask line"
fi

exit 0
