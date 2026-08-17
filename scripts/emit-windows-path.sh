#!/usr/bin/env bash
# Convert a path for EMISSION across the Git Bash -> Windows-native boundary.
#
#   scripts/emit-windows-path.sh <path>...       print each path in mixed form
#                                                (C:/dir/file) - the default,
#                                                because forward slashes survive
#                                                shell and source-literal quoting
#   scripts/emit-windows-path.sh -w <path>...    print each path in backslash
#                                                form (C:\dir\file), for a
#                                                consumer that requires it
#                                                (cmd, some PowerShell providers)
#
# Exit: 0 converted (or passed through on a POSIX host); 2 usage error, cygpath
# missing, or a conversion that failed. There is NO exit code that means "I gave
# you the path unconverted on Windows" - see FAIL LOUD below.
#
# WHY THIS EXISTS. Git Bash spells `D:\dir` as `/d/dir`. Handed to a
# Windows-native consumer - PowerShell, cmd, or a native interpreter such as
# Windows Python - the leading `/` anchors to the root of the CURRENT DRIVE, so
# the literal becomes `<current-drive>:\d\dir`. Nothing errors: the consumer
# happily creates the phantom tree and writes there. #2834 is the worked case -
# a verification harness whose fixtures landed under a phantom drive-root tree,
# which silently turned two of its own test cases into duplicates of a third.
# The drive-root litter was the visible symptom; the invalid test results were
# the actual cost. `docs/conventions/windows-path-emit/README.md` owns the rule
# this script implements, including the rule that ranks ABOVE it: prefer a path
# the native side computes itself from a working directory it already owns, and
# reach for this conversion only when an absolute path genuinely has to cross.
#
# MIXED FORM (`cygpath -m`) IS THE DEFAULT, not `-w`. Both spellings are correct
# to the Win32 API, which accepts `/` and `\` interchangeably as separators. The
# difference is what happens on the way there: a backslash path embedded in a
# shell string, a Python literal, or a JSON value is one escape rule away from
# becoming something else (`C:\temp\new` carries a newline in a Python literal),
# and each layer it crosses is another chance to lose a separator. Mixed form has
# no escape hazard in any of those layers. `-w` stays available for the consumer
# that genuinely rejects forward slashes.
#
# FAIL LOUD. This helper is on an EMIT path, so it exits non-zero rather than
# returning the input unconverted when cygpath is missing or fails. That is the
# deliberate opposite of `lib/hook-utils.sh`'s host-gated path helpers, which
# fail OPEN because their results feed a COMPARISON - a degraded comparison
# answers a question slightly worse, while a degraded emitted path writes real
# bytes to the wrong place, unobserved. `hook::normalize_path` in particular is
# documented as comparison-only ("the emitted path is always the caller's
# original") and must never be used to produce a path a native consumer reads.
#
# On a non-Windows host every path is already in its native form, so each
# argument is printed unchanged and the exit is 0. That keeps a script that
# routes its paths through this helper portable rather than Windows-only.
set -uo pipefail

usage() {
  printf 'usage: emit-windows-path.sh [-m|--mixed | -w|--backslash] <path>...\n' >&2
  printf '       -m  mixed form, C:/dir/file (default)\n' >&2
  printf '       -w  backslash form, C:\\dir\\file\n' >&2
}

form="-m"
while (($# > 0)); do
  case "$1" in
  -w | --backslash)
    form="-w"
    shift
    ;;
  -m | --mixed)
    form="-m"
    shift
    ;;
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
done

if (($# == 0)); then
  echo "emit-windows-path.sh: at least one path is required" >&2
  usage
  exit 2
fi

# Host gate, first and unconditional. On a POSIX host there is no MSYS->native
# boundary to cross and no cygpath to cross it with; the argument IS the native
# spelling. Pass through and exit 0 so callers stay cross-platform.
case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*)
  for p in "$@"; do printf '%s\n' "$p"; done
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
