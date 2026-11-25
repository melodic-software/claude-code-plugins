#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config-root.sh
source "$SCRIPT_DIR/config-root.sh"

say() { printf 'verification: %s\n' "${1//[[:cntrl:]]/ }"; }
fallback() {
  say "light ($1)"
  exit 0
}

usage="default; usage: read-verification.sh --plugin <plugin> --skill <skill> [--file <path>]"
plugin="" skill="" fixed=""
while (($#)); do
  case "$1" in
  --plugin | --skill | --file)
    (($# >= 2)) || fallback "$usage"
    case "$1" in
    --plugin) plugin="$2" ;;
    --skill) skill="$2" ;;
    *) fixed="$2" ;;
    esac
    shift 2
    ;;
  *) fallback "$usage" ;;
  esac
done
name='^[a-z0-9][a-z0-9-]*$'
[[ "$plugin" =~ $name && "$skill" =~ $name ]] ||
  fallback "default; --plugin and --skill take a name of lowercase letters, digits and -"
if [[ -n "$fixed" ]] && [[ ! "$fixed" =~ ^[A-Za-z0-9._/-]+\.yaml$ || "$fixed" == [/-]* || "$fixed" == *..* ]]; then
  fallback "default; --file '$fixed' is not a repository-relative .yaml path"
fi

err="$(mktemp)" || fallback "default; team layer skipped: no temporary file for the reader"
trap 'rm -f "$err"' EXIT
rc=0
if [[ -n "$fixed" ]]; then
  team="$(bash "$SCRIPT_DIR/default-branch-file.sh" --path "$fixed" 2>"$err")" || rc=$?
else
  team="$(bash "$SCRIPT_DIR/default-branch-file.sh" --plugin "$plugin" 2>"$err")" || rc=$?
fi
line="$(tail -n 1 "$err")"
line="${line#default-branch-file: }"
case "$rc" in
0 | 1) ;;
*) fallback "default; team layer skipped: $line" ;;
esac
file="${line%% at origin/*}"
at="at ${line#"$file at "}"

resolve() {
  local text="${2-}" records v k
  LEVEL=light KEY="" ERR=""
  if [[ "$1" == worktree ]]; then
    [[ -n "$root" && -f "$root/$file" ]] || return
    text="$(<"$root/$file")"
  fi
  records="$(LC_ALL=C awk -f "$SCRIPT_DIR/yaml-subset.awk" <<<"$text" 2>/dev/null)" || {
    LEVEL=standard ERR="$file does not parse or repeats a key"
    return
  }
  for k in "verification_skills.$skill" verification; do
    if awk -F '\t' -v k="$k." 'index($1, k) == 1 { found = 1 } END { exit !found }' <<<"$records"; then
      LEVEL=standard ERR="$file $k is a list or map, not off, light, standard or strict"
      return
    fi
    v="$(awk -F '\t' -v k="$k" '$1 == k { print substr($0, length($1) + 2); exit }' <<<"$records")"
    [[ -z "$v" ]] || break
  done
  [[ -n "$v" ]] || return
  if [[ "$v" =~ ^(off|light|standard|strict)$ ]]; then
    LEVEL="$v" KEY="$k"
  else
    LEVEL=standard ERR="$file $k=$v is not off, light, standard or strict"
  fi
}

describe() {
  if [[ -n "$ERR" ]]; then
    printf 'standard (default; %s' "$ERR"
  elif [[ -n "$KEY" ]]; then
    printf '%s (%s %s' "$LEVEL" "$file" "$KEY"
  else
    printf 'light (default; %s sets no level' "$file"
  fi
}

if ((rc == 0)); then
  resolve team "$team"
else
  LEVEL=light KEY="" ERR=""
fi
team_level="$LEVEL"
say "$(describe) $at)"

root="$(git -C "$(config_root_resolve)" rev-parse --show-toplevel 2>/dev/null)" || root=""
resolve worktree
if [[ "$LEVEL" != "$team_level" ]]; then
  branch="${at#at origin/}"
  say "the working tree's copy gives $(describe)); the origin/${branch%%, commit *} copy ($team_level) applied"
fi
exit 0
