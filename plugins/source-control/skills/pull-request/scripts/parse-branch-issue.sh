#!/usr/bin/env bash
# Exits 1 with no stdout if the branch does not match.
set -uo pipefail

KEY="branch_issue_pattern"

EXPLAIN=0
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--explain" ]]; then EXPLAIN=1; else ARGS+=("$arg"); fi
done
set -- ${ARGS[@]+"${ARGS[@]}"}

BRANCH="${1:-}"
[[ -n "$BRANCH" ]] || BRANCH="$(git branch --show-current 2>/dev/null || true)"
[[ -n "$BRANCH" ]] || exit 1

note() { echo "parse-branch-issue: $*" >&2; }

# shellcheck source=../../../lib/config-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/config-root.sh" || exit 1
# shellcheck source=../../../lib/convention-key.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/convention-key.sh" || exit 1

STOP="resolution stopped, no issue id emitted"

FENCE_OPEN='^(```+|~~~+)'
FENCE_CLOSE='^(```+|~~~+)$'

section_value() {
  local file="$1" line state=0 fence="" value="" first=1
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((first)); then
      line="${line#$'\xef\xbb\xbf'}"
      first=0
    fi
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -n "$fence" ]]; then
      if [[ "$line" =~ $FENCE_CLOSE && "${line:0:1}" == "${fence:0:1}" && ${#line} -ge ${#fence} ]]; then
        if [[ "$state" -eq 1 ]]; then
          if [[ -z "$value" ]]; then
            note "${file}: ## ${KEY} holds an empty code fence; ${STOP}"
            return 1
          fi
          state=2
        fi
        fence=""
      elif [[ "$state" -eq 1 && -z "$value" && -n "$line" ]]; then
        value="$line"
      fi
      continue
    fi
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      if [[ "$line" =~ ^##[[:space:]]+${KEY}([[:space:]]+#+)?$ ]]; then
        [[ "$state" -eq 0 ]] && state=1
      elif [[ "${line,,}" == *"$KEY"* ]]; then
        note "${file}: near-miss heading for ## ${KEY}; ${STOP}"
        return 1
      elif [[ "$state" -eq 1 ]]; then
        note "${file}: ## ${KEY} holds no value; ${STOP}"
        return 1
      fi
      continue
    fi
    if [[ "$line" =~ $FENCE_OPEN ]]; then
      fence="${BASH_REMATCH[1]}"
      continue
    fi
    [[ "$state" -eq 1 && -n "$line" ]] || continue
    if [[ "$line" =~ ^#{1,6}([[:space:]]|$) ]]; then
      note "${file}: ## ${KEY} starts with a heading, not a pattern; ${STOP}"
      return 1
    fi
    if [[ "$line" == '<!--'* ]]; then
      note "${file}: ## ${KEY} starts with an HTML comment, not a pattern; ${STOP}"
      return 1
    fi
    while [[ "$line" == \`* ]]; do line="${line#\`}"; done
    while [[ "$line" == *\` ]]; do line="${line%\`}"; done
    if [[ -z "$line" ]]; then
      note "${file}: ## ${KEY} holds no value; ${STOP}"
      return 1
    fi
    value="$line"
    state=2
  done <"$file"
  if [[ "$state" -eq 1 ]]; then
    if [[ -n "$fence" ]]; then
      note "${file}: ## ${KEY} holds an unterminated code fence; ${STOP}"
    else
      note "${file}: ## ${KEY} holds no value; ${STOP}"
    fi
    return 1
  fi
  [[ -z "$value" ]] || printf '%s\n' "$value"
  return 0
}

pattern_limit() {
  local p="$1" i j c d b depth=0 inner rest
  local n=${#p}
  local -a has=(0)
  if ((n > 200)); then
    echo "is too long (over 200 characters)"
    return
  fi
  for ((i = 0; i < n; i++)); do
    c="${p:i:1}"
    case "$c" in
      \\) i=$((i + 1)) ;;
      '[')
        j=$((i + 1))
        [[ "${p:j:1}" == "^" ]] && j=$((j + 1))
        [[ "${p:j:1}" == "]" ]] && j=$((j + 1))
        while ((j < n)); do
          c="${p:j:1}"
          d="${p:j+1:1}"
          if [[ "$c" == "[" && -n "$d" && ":.=" == *"$d"* ]]; then
            rest="${p:j+2}"
            [[ "$rest" == *"$d]"* ]] || break
            rest="${rest%%"$d]"*}"
            j=$((j + ${#rest} + 4))
            continue
          fi
          [[ "$c" == "]" ]] && break
          j=$((j + 1))
        done
        i=$j
        ;;
      '(')
        depth=$((depth + 1))
        has[depth]=0
        ;;
      ')')
        ((depth > 0)) || continue
        inner=${has[depth]}
        depth=$((depth - 1))
        if ((inner)); then
          if [[ "${p:i+1:1}" == [*+?'{'] ]]; then
            echo "applies a quantifier to a group that holds one (nested quantifier)"
            return
          fi
          has[depth]=1
        fi
        ;;
      '{')
        if [[ "${p:i}" =~ ^\{([0-9]*)(,([0-9]*))?\} ]]; then
          for b in "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"; do
            if [[ -n "$b" ]] && ((${#b} > 2 || 10#$b > 16)); then
              echo "has a repetition bound over 16"
              return
            fi
          done
        fi
        has[depth]=1
        ;;
      '*' | '+' | '?') has[depth]=1 ;;
      *) ;;
    esac
  done
}

usable_pattern() {
  local src="$1" value="$2" outcome="$3" limit reason=""
  limit="$(pattern_limit "$value")"
  if [[ -n "$limit" ]]; then
    reason="$limit"
  elif [[ "$value" =~ \\[1-9] ]]; then
    reason="uses a backreference, which is not allowed"
  else
    { [[ "" =~ $value ]]; } 2>/dev/null
    (($? != 2)) || reason="is an invalid ERE"
  fi
  [[ -z "$reason" ]] && return 0
  note "${src}: ${KEY} ${reason}; ${outcome}"
  return 1
}

REPO_ROOT="$(config_root_resolve)"

SETUP_HINT="run /source-control:setup apply to move it, which deletes the old file"
old_location() { note "old location ${1}: $2; move its keys to ${3}; ${SETUP_HINT}"; }

LAYERS=()
USER_LAYER="${HOME:-}/.claude/source-control.md"
if [[ -n "$REPO_ROOT" ]]; then
  case "$(config_root_classify "$REPO_ROOT")" in
    home) note "team and personal override not applicable: project root is the home directory (or an ancestor of it)" ;;
    non-repo) note "team and personal override not applicable: project root is not inside a git repository" ;;
    *)
      PERSONAL_YAML="${REPO_ROOT}/${CONVENTION_KEY_LOCAL_REL}"
      personal_override="${REPO_ROOT}/${CONVENTION_KEY_OLD_LOCAL_REL}"
      TEAM_YAML="${REPO_ROOT}/${CONVENTION_KEY_YAML_REL}"
      [[ -f "$PERSONAL_YAML" ]] && LAYERS+=("$PERSONAL_YAML")
      if [[ -f "$personal_override" ]] && ! config_root_paths_same "$personal_override" "$USER_LAYER"; then
        if [[ -f "$PERSONAL_YAML" ]]; then
          old_location "$personal_override" "not read, since ${CONVENTION_KEY_LOCAL_REL} supplies the personal override" "$PERSONAL_YAML"
        else
          LAYERS+=("$personal_override")
          old_location "$personal_override" "still read as the personal override" "$PERSONAL_YAML"
        fi
      fi
      if convention_key_tracked "$REPO_ROOT" "$CONVENTION_KEY_YAML_REL"; then
        LAYERS+=("$TEAM_YAML")
      elif [[ -e "$TEAM_YAML" ]]; then
        note "${CONVENTION_KEY_YAML_REL} is not tracked by git, so it is not a config layer"
      fi
      ;;
  esac
fi
if [[ -n "${HOME:-}" && -f "$USER_LAYER" ]]; then
  LAYERS+=("$USER_LAYER")
  old_location "$USER_LAYER" "still read as the lowest layer" \
    "${CONVENTION_KEY_YAML_REL} (team) or ${CONVENTION_KEY_LOCAL_REL} (personal) in each repository that needs it"
fi

layer_label() {
  case "$1" in
    "${TEAM_YAML:-}") echo "$CONVENTION_KEY_YAML_REL" ;;
    "${PERSONAL_YAML:-}") echo "$CONVENTION_KEY_LOCAL_REL" ;;
    "${personal_override:-}") echo "old personal override ${CONVENTION_KEY_OLD_LOCAL_REL}" ;;
    "$USER_LAYER") echo "old user-global .claude/source-control.md in the home directory" ;;
    *) echo "$1" ;;
  esac
}

PATTERN="" SOURCE="" LABEL=""
for layer in ${LAYERS[@]+"${LAYERS[@]}"}; do
  if [[ "$layer" == "${TEAM_YAML:-}" || "$layer" == "${PERSONAL_YAML:-}" ]]; then
    rel="$CONVENTION_KEY_YAML_REL"
    [[ "$layer" == "${PERSONAL_YAML:-}" ]] && rel="$CONVENTION_KEY_LOCAL_REL"
    value="$(convention_key_yaml_value "$REPO_ROOT" "$KEY" "$rel")"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      note "${rel} could not be parsed; ${STOP}"
      exit 1
    fi
  else
    value="$(section_value "$layer")" || exit 1
  fi
  [[ -n "$value" ]] || continue
  usable_pattern "$layer" "$value" "$STOP" || exit 1
  PATTERN="$value" SOURCE="$layer" LABEL="$(layer_label "$layer")"
  break
done

if [[ -z "$PATTERN" ]]; then
  LEGACY="${2:-}"
  # shellcheck disable=SC2016  # matching the literal placeholder text, not expanding it
  [[ "$LEGACY" == *'${user_config'* ]] && LEGACY=""
  [[ -n "$LEGACY" ]] || LEGACY="${CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN:-}"
  if [[ -n "$LEGACY" ]] && usable_pattern userConfig "$LEGACY" "ignored, default applies"; then
    PATTERN="$LEGACY" SOURCE="userConfig" LABEL="userConfig"
    note "the ${KEY} userConfig is deprecated; set ${KEY} in ${CONVENTION_KEY_YAML_REL} instead."
  fi
fi
if [[ -z "$PATTERN" && "${3:-}" == "--no-default" ]]; then
  exit 3
fi
[[ -n "$PATTERN" ]] || PATTERN='^[a-z]+/(routine-issue-)?([0-9]+)-' SOURCE="default" LABEL="default"
[[ "$EXPLAIN" -eq 0 ]] || note "${KEY} layer: ${LABEL}"

[[ "$BRANCH" =~ $PATTERN ]] || exit 1

n=${#BASH_REMATCH[@]}
if [[ "$n" -lt 2 ]]; then
  note "${SOURCE}: ${KEY} has no capture group; no issue id emitted"
  exit 1
fi
id="${BASH_REMATCH[n - 1]}"
if [[ ! "$id" =~ ^([0-9]+|[A-Za-z][A-Za-z0-9_]*-[0-9]+)$ ]]; then
  note "${SOURCE}: ${KEY} captured a non-numeric id that is not a tracker key either; no issue id emitted"
  exit 1
fi
echo "$id"
