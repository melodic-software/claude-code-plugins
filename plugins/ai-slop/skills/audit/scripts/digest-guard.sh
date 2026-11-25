#!/usr/bin/env bash
# Exit: 0 recorded, created or matching; 1 mismatch; 2 usage error or refusal.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_LOGICAL="$(cd -L "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
LANE_SUFFIX=/plugins/ai-slop/skills/audit/scripts

usage() {
  cat >&2 <<'EOF'
Record a file's sha256 and check it again before each fix write.
Usage: digest-guard.sh init <run-dir> | record <absolute file> <run-dir> | check <absolute file> <run-dir>
  init    create the run directory (ai-slop-fix-<TS>[-<n>]), which must not exist yet
  record  write the file's digest under <run-dir>/digests/
  check   compare the file's digest with the recorded one; prints match or mismatch
The run directory's parent must sit under AI_SLOP_STATE_ROOT, a CI lane's scratch, or itself.
Exit: 0 recorded, created or matching; 1 mismatch; 2 usage error or refusal.
EOF
}

die() {
  echo "digest-guard.sh: $*" >&2
  exit 2
}

sha256_hex() {
  local line
  if command -v sha256sum >/dev/null 2>&1; then
    line="$(sha256sum)" || die "cannot digest"
  else
    line="$(shasum -a 256)" || die "cannot digest"
  fi
  printf '%s' "${line%% *}"
}

resolve_run() {
  local run="$1" name parent root
  name="$(basename -- "$run")"
  [[ "$name" =~ ^ai-slop-fix-[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]] ||
    die "not a run directory name: $name"
  parent="$(cd -P -- "$(dirname -- "$run")" 2>/dev/null && pwd)" ||
    die "the run directory's parent does not exist: $run"
  if [[ -n "${AI_SLOP_STATE_ROOT:-}" ]]; then
    root="$AI_SLOP_STATE_ROOT"
  elif [[ "$SCRIPT_DIR_LOGICAL" == */.lane"$LANE_SUFFIX" ]]; then
    root="${SCRIPT_DIR_LOGICAL%"$LANE_SUFFIX"}/scratch"
  elif [[ "$SCRIPT_DIR" == */.lane"$LANE_SUFFIX" ]]; then
    root="${SCRIPT_DIR%"$LANE_SUFFIX"}/scratch"
  else
    root="$parent"
  fi
  root="$(cd -P -- "$root" 2>/dev/null && pwd)" || die "the state root does not exist: $root"
  [[ "$parent" == "$root" || "$parent" == "${root%/}/"* ]] ||
    die "the run directory is outside the state root $root: $run"
  [[ ! -L "$parent/$name" ]] || die "the run directory is a symbolic link: $parent/$name"
  printf '%s/%s' "${parent%/}" "$name"
}

ensure_dir() {
  [[ ! -L "$1" ]] || die "a symbolic link stands at $1"
  [[ -d "$1" ]] || mkdir -- "$1" || die "cannot create $1"
}

[[ $# -ge 1 ]] || { usage; exit 2; }
cmd="$1"
shift
case "$cmd" in
init)
  [[ $# -eq 1 ]] || die "init takes one run directory"
  run="$(resolve_run "$1")"
  [[ ! -e "$run" ]] || die "the run directory exists already: $run"
  mkdir -- "$run" || die "cannot create $run"
  printf '%s\n' "$run"
  ;;
record | check)
  [[ $# -eq 2 ]] || die "$cmd takes a file and a run directory"
  file="$1"
  [[ "$file" == /* ]] || die "not an absolute path: $file"
  [[ -f "$file" ]] || die "not a regular file: $file"
  [[ -r "$file" ]] || die "cannot read $file"
  run="$(resolve_run "$2")"
  state="$run/digests/$(printf '%s' "$file" | sha256_hex).sha256"
  digest="$(sha256_hex <"$file")"
  if [[ "$cmd" == record ]]; then
    ensure_dir "$run"
    ensure_dir "$run/digests"
    [[ ! -L "$state" ]] || die "a symbolic link stands at $state"
    tmp="$(mktemp "$run/digests/.tmp.XXXXXX")" || die "cannot write in $run/digests"
    { printf '%s\n' "$digest" >"$tmp" && mv -f -- "$tmp" "$state"; } || {
      rm -f -- "$tmp"
      die "cannot write $state"
    }
  else
    [[ -f "$state" && ! -L "$state" ]] || die "no digest recorded for $file in $run"
    if [[ "$(<"$state")" == "$digest" ]]; then
      echo match
    else
      echo mismatch
      exit 1
    fi
  fi
  ;;
--help | -h) usage; exit 0 ;;
*) usage; exit 2 ;;
esac
