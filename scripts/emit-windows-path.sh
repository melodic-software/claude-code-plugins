#!/usr/bin/env bash
set -uo pipefail

usage() {
  printf 'usage: emit-windows-path.sh [-m|--mixed | -w|--backslash] <path>...\n' >&2
  printf '       -m  mixed form, C:/dir/file (default)\n' >&2
  printf '       -w  backslash form, C:\\dir\\file\n' >&2
}

form="-m"
while (($# > 0)); do
  case "$1" in
  -w | --backslash) form="-w" ;;
  -m | --mixed) form="-m" ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    break
    ;;
  -*)
    echo "emit-windows-path.sh: unknown option: $1" >&2
    usage
    exit 2
    ;;
  *) break ;;
  esac
  shift
done

if (($# == 0)); then
  echo "emit-windows-path.sh: at least one path is required" >&2
  usage
  exit 2
fi

case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*)
  printf '%s\n' "$@"
  exit 0
  ;;
esac

if ! command -v cygpath >/dev/null 2>&1; then
  echo "emit-windows-path.sh: cygpath not found on a Windows host; refusing to emit an unconverted MSYS path." >&2
  echo "  cygpath ships with Git Bash, the supported Windows shell for this repo." >&2
  exit 2
fi

rc=0
for p in "$@"; do
  if converted=$(cygpath "$form" -- "$p" 2>/dev/null) && [[ -n "$converted" ]]; then
    printf '%s\n' "$converted"
  else
    echo "emit-windows-path.sh: cygpath $form failed for: $p" >&2
    rc=2
  fi
done
exit "$rc"
