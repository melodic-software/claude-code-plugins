#!/bin/sh
# GENERATED from lib/resolve-convention-pattern.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=sh
set -u

readonly CC_ERE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'
# shellcheck disable=SC2016  # backticks are a literal part of the deferral marker, not a substitution
readonly PR_DEFERRAL='Same as `subject_pattern`.'

readonly TEAM_YAML_REL="docs/conventions/source-control.yaml"
readonly PERSONAL_YAML_REL="docs/conventions/source-control.local.yaml"
readonly WELL_KNOWN_NEUTRAL="docs/conventions/source-control/commit-convention.yml"

case "${1:-}" in
--help | -h)
  cat <<'EOF'
Resolve the enforcement pattern for a source-control convention key to a POSIX ERE.
Usage: resolve-convention-pattern.sh [--layer] <repo_root> <subject_pattern|pr_title_pattern>
  --layer  print the repo-relative file that supplied the key's value instead of the pattern
Exit status:
  0  a pattern was emitted (enforce it)
  1  no enforcement (unresolved, or not expressible in ERE; stdout empty)
  2  usage error
EOF
  exit 0
  ;;
*) ;;
esac

layer_mode=0
if [ "${1:-}" = "--layer" ]; then
  layer_mode=1
  shift
fi

repo_root="${1:-}"
key="${2:-}"

if [ -z "$repo_root" ] || [ -z "$key" ]; then
  echo "resolve-convention-pattern: usage: resolve-convention-pattern.sh [--layer] <repo_root> <subject_pattern|pr_title_pattern>" >&2
  exit 2
fi
case "$key" in
subject_pattern | pr_title_pattern) ;;
*)
  echo "resolve-convention-pattern: key must be subject_pattern or pr_title_pattern, got '$key'" >&2
  exit 2
  ;;
esac

case "$0" in
*/*) self_dir="${0%/*}" ;;
*) self_dir=. ;;
esac
readonly YAML_PARSER="$self_dir/yaml-subset.awk"

readonly TEAM_YAML="$repo_root/$TEAM_YAML_REL"

nl='
'
tab="$(printf '\t')"
cr="$(printf '\r')"
bom="$(printf '\357\273\277')"

rcp_git() {
  git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"
}

yaml_scalar() {
  yaml_v="${2#"${1}":}"
  yaml_v="${yaml_v#"${yaml_v%%[![:space:]]*}"}"
  yaml_v="${yaml_v%"${yaml_v##*[![:space:]]}"}"
  case "$yaml_v" in
  \'*\' | \"*\")
    yaml_v="${yaml_v#?}"
    yaml_v="${yaml_v%?}"
    ;;
  *) ;;
  esac
}

NEUTRAL_HAS_DIALECT=""
NEUTRAL_DIALECT=""
NEUTRAL_HAS_SUBJECT=""
NEUTRAL_SUBJECT=""
NEUTRAL_HAS_PR_TITLE=""
NEUTRAL_PR_TITLE=""

read_neutral() {
  [ -n "$NEUTRAL_FILE" ] || return 0
  if [ ! -r "$NEUTRAL_FILE" ]; then
    printf '%s\n' "resolve-convention-pattern: cannot read $NEUTRAL_REL; enforcement disabled (fix the file's permissions)." >&2
    exit 1
  fi
  while IFS= read -r rn_line || [ -n "$rn_line" ]; do
    case "$rn_line" in
    dialect:*)
      [ -z "$NEUTRAL_HAS_DIALECT" ] || continue
      yaml_scalar dialect "$rn_line"
      NEUTRAL_HAS_DIALECT=1
      NEUTRAL_DIALECT="$yaml_v"
      ;;
    subject_pattern:*)
      [ -z "$NEUTRAL_HAS_SUBJECT" ] || continue
      yaml_scalar subject_pattern "$rn_line"
      NEUTRAL_HAS_SUBJECT=1
      NEUTRAL_SUBJECT="$yaml_v"
      ;;
    pr_title_pattern:*)
      [ -z "$NEUTRAL_HAS_PR_TITLE" ] || continue
      yaml_scalar pr_title_pattern "$rn_line"
      NEUTRAL_HAS_PR_TITLE=1
      NEUTRAL_PR_TITLE="$yaml_v"
      ;;
    *) ;;
    esac
  done <"$NEUTRAL_FILE"
}

neutral_key() {
  case "$1" in
  subject_pattern)
    nk_has="$NEUTRAL_HAS_SUBJECT"
    nk_v="$NEUTRAL_SUBJECT"
    ;;
  *)
    nk_has="$NEUTRAL_HAS_PR_TITLE"
    nk_v="$NEUTRAL_PR_TITLE"
    ;;
  esac
}

in_repo_or_exit() {
  ir_file="$repo_root/$1"
  if [ -L "$ir_file" ]; then
    printf '%s\n' "resolve-convention-pattern: $2 '$1' is a symlink; the file must be a regular file — enforcement disabled." >&2
    exit 1
  fi
  canon_root="$(cd "$repo_root" 2>/dev/null && pwd -P)"
  canon_dir="$(cd "${ir_file%/*}" 2>/dev/null && pwd -P)"
  canon_prefix="$canon_root/"
  canon_dir_slash="$canon_dir/"
  if [ -z "$canon_root" ] || [ -z "$canon_dir" ] ||
    [ "${canon_dir_slash#"$canon_prefix"}" = "$canon_dir_slash" ]; then
    printf '%s\n' "resolve-convention-pattern: $2 '$1' resolves outside the repository root (symlinked path segment); enforcement disabled." >&2
    exit 1
  fi
}

YAML_ACTIVE=0
YAML_RECORDS=""
YAML_REL=""
YAML_PATH=""

load_yaml() {
  YAML_REL="$1"
  YAML_PATH="$repo_root/$1"
  in_repo_or_exit "$1" "$2"
  if [ ! -f "$YAML_PARSER" ]; then
    printf '%s\n' "resolve-convention-pattern: cannot read $1: its parser, yaml-subset.awk, is not beside the resolver; enforcement disabled." >&2
    exit 1
  fi
  if ! YAML_RECORDS="$(LC_ALL=C awk -v STRICT=1 -f "$YAML_PARSER" <"$YAML_PATH" 2>/dev/null)"; then
    yaml_err="${YAML_RECORDS##*"$nl"}"
    yaml_err="${yaml_err#error"$tab"}"
    printf '%s\n' "resolve-convention-pattern: $1 does not parse (line ${yaml_err%%"$tab"*}: ${yaml_err#*"$tab"}); enforcement disabled." >&2
    exit 1
  fi
  YAML_ACTIVE=1
}

if [ -f "$TEAM_YAML" ] &&
  rcp_git -C "$repo_root" ls-files --error-unmatch -- "$TEAM_YAML_REL" >/dev/null 2>&1; then
  load_yaml "$TEAM_YAML_REL" "the team file"
fi

yaml_lookup() {
  YAML_HAS=0
  YAML_VAL=""
  [ "$YAML_ACTIVE" -eq 1 ] || return 0
  yl_rest="$nl$YAML_RECORDS"
  case "$yl_rest" in
  *"$nl$1$tab"*)
    yl_rest="${yl_rest#*"$nl$1$tab"}"
    YAML_VAL="${yl_rest%%"$nl"*}"
    YAML_HAS=1
    ;;
  *) ;;
  esac
  return 0
}

yaml_bare_key() {
  yb_first=1
  while IFS= read -r yb_line || [ -n "$yb_line" ]; do
    yb_line="${yb_line%"$cr"}"
    if [ "$yb_first" -eq 1 ]; then
      yb_line="${yb_line#"$bom"}"
      yb_first=0
    fi
    case "$yb_line" in
    "$1:"*) yb_rest="${yb_line#"$1:"}" ;;
    "\"$1\":"*) yb_rest="${yb_line#"\"$1\":"}" ;;
    "'$1':"*) yb_rest="${yb_line#"'$1':"}" ;;
    *) continue ;;
    esac
    yb_rest="${yb_rest#"${yb_rest%%[![:space:]]*}"}"
    case "$yb_rest" in
    "" | "#"*) return 0 ;;
    *) ;;
    esac
  done <"$YAML_PATH"
  return 1
}

check_yaml_key() {
  [ "$YAML_ACTIVE" -eq 1 ] || return 0
  yaml_lookup "$1"
  if [ "$YAML_HAS" -eq 1 ]; then
    [ -n "$YAML_VAL" ] && return 0
  else
    case "$nl$YAML_RECORDS" in
    *"$nl$1."*) ;; # carried as a list or a mapping
    *) yaml_bare_key "$1" || return 0 ;;
    esac
  fi
  printf '%s\n' "resolve-convention-pattern: $YAML_REL carries '$1' without one non-empty value; a carried key must hold one value (delete the line to fall back) — enforcement disabled." >&2
  exit 1
}

check_yaml_dialect() {
  yaml_lookup dialect
  if [ -n "$YAML_VAL" ] && [ "$YAML_VAL" != "posix-ere" ]; then
    printf '%s\n' "resolve-convention-pattern: $YAML_REL declares dialect '$YAML_VAL'; enforcement consumes posix-ere only — enforcement disabled." >&2
    exit 1
  fi
}
check_yaml_dialect

NEUTRAL_FILE=""
NEUTRAL_REL=""
NEUTRAL_READY=0
resolve_neutral() {
  NEUTRAL_READY=1
  if [ ! -f "$repo_root/$WELL_KNOWN_NEUTRAL" ] ||
    ! rcp_git -C "$repo_root" ls-files --error-unmatch -- "$WELL_KNOWN_NEUTRAL" >/dev/null 2>&1; then
    return 0
  fi
  NEUTRAL_FILE="$repo_root/$WELL_KNOWN_NEUTRAL"
  NEUTRAL_REL="$WELL_KNOWN_NEUTRAL"
  in_repo_or_exit "$WELL_KNOWN_NEUTRAL" "the folder-form file"
  read_neutral
  if [ -n "$NEUTRAL_DIALECT" ] && [ "$NEUTRAL_DIALECT" != "posix-ere" ]; then
    printf '%s\n' "resolve-convention-pattern: $NEUTRAL_REL declares dialect '$NEUTRAL_DIALECT'; enforcement consumes posix-ere only — enforcement disabled." >&2
    exit 1
  fi
}

check_neutral_key() {
  neutral_key "$1"
  [ -n "$nk_has" ] || return 0
  [ -n "$nk_v" ] && return 0
  printf '%s\n' "resolve-convention-pattern: $NEUTRAL_REL carries '$1' with an empty value; a carried key must hold a value (delete the line to leave the key unset) — enforcement disabled." >&2
  exit 1
}

team_value() {
  TV=""
  TV_LAYER=""
  yaml_lookup "$1"
  if [ "$YAML_HAS" -eq 1 ]; then
    TV="$YAML_VAL"
    TV_LAYER="$TEAM_YAML_REL"
    return 0
  fi
  [ "$NEUTRAL_READY" -eq 1 ] || return 0
  neutral_key "$1"
  if [ -n "$nk_v" ]; then
    TV="$nk_v"
    TV_LAYER="$NEUTRAL_REL"
  fi
  return 0
}

is_non_ere() {
  case "$1" in
  *'(?'*) return 0 ;;
  *\\[a-zA-Z0-9]*) return 0 ;;
  *) return 1 ;;
  esac
}

raw_value() {
  team_value "$1"
  RV="$TV"
  RV_LAYER="$TV_LAYER"
  [ "$RV" = "Conventional Commits" ] && RV="$CC_ERE"
  return 0
}

check_yaml_key "$key"
yaml_lookup "$key"
key_in_yaml="$YAML_HAS"
subject_in_yaml=1
if [ "$key" = "pr_title_pattern" ] &&
  { [ "$YAML_HAS" -eq 0 ] || [ "$YAML_VAL" = "$PR_DEFERRAL" ]; }; then
  check_yaml_key subject_pattern
  yaml_lookup subject_pattern
  subject_in_yaml="$YAML_HAS"
fi
if [ "$key_in_yaml" -eq 0 ] || [ "$subject_in_yaml" -eq 0 ]; then
  resolve_neutral
  [ "$key_in_yaml" -eq 1 ] || check_neutral_key "$key"
  [ "$subject_in_yaml" -eq 1 ] || check_neutral_key subject_pattern
fi

raw_value "$key"
value="$RV"
layer="$RV_LAYER"

if [ "$key" = "pr_title_pattern" ] && [ "$TV" = "$PR_DEFERRAL" ]; then
  raw_value "subject_pattern"
  value="$RV"
fi

read_personal() {
  [ -f "$repo_root/$PERSONAL_YAML_REL" ] || return 0
  ignore_rc=0
  rcp_git -C "$repo_root" check-ignore -q -- "$PERSONAL_YAML_REL" >/dev/null 2>&1 || ignore_rc=$?
  if [ "$ignore_rc" -eq 1 ]; then
    printf '%s\n' "resolve-convention-pattern: $PERSONAL_YAML_REL is not ignored by git (it is tracked, or no .gitignore, .git/info/exclude or core.excludesFile rule matches it); the personal layer is read only while git ignores it — enforcement disabled." >&2
    exit 1
  fi
  if [ "$ignore_rc" -ne 0 ]; then
    printf '%s\n' "resolve-convention-pattern: git could not tell whether $PERSONAL_YAML_REL is ignored (git check-ignore exit $ignore_rc); the personal layer is read only while git ignores it — enforcement disabled." >&2
    exit 1
  fi
  load_yaml "$PERSONAL_YAML_REL" "the personal file"
  check_yaml_dialect
  check_yaml_key subject_pattern
  yaml_lookup subject_pattern
  value="$YAML_VAL"
  layer="$PERSONAL_YAML_REL"
  [ "$value" != "Conventional Commits" ] || value="$CC_ERE"
}
if [ -z "$value" ] && [ "$key" = "subject_pattern" ]; then
  read_personal
fi

[ -n "$value" ] || exit 1

if is_non_ere "$value"; then
  printf '%s\n' "resolve-convention-pattern: $key is not POSIX ERE (a PCRE-only construct: a (?...) group, or a backslash-letter/backslash-digit escape such as \\d \\A \\t \\1); enforcement disabled -- author the pattern in POSIX ERE (e.g. [0-9] not \\d) to enable the gate." >&2
  exit 1
fi

# grep exits above 1 on an error, such as an expression that does not compile:
# https://pubs.opengroup.org/onlinepubs/9799919799/utilities/grep.html#tag_20_55_14
grep_rc=0
grep -E -- "$value" </dev/null >/dev/null 2>&1 || grep_rc=$?
if [ "$grep_rc" -ge 2 ]; then
  printf '%s\n' "resolve-convention-pattern: $key does not compile as POSIX ERE; enforcement disabled." >&2
  exit 1
fi

if [ "$layer_mode" -eq 1 ]; then
  printf '%s\n' "$layer"
else
  printf '%s\n' "$value"
fi
exit 0
