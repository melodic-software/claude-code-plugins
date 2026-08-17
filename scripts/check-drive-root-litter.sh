#!/usr/bin/env bash
# Detect the on-disk fingerprint of an unconverted MSYS path handed to a
# Windows-native consumer: a directory sitting at a drive root whose name is a
# single letter that is ITSELF a mounted drive.
#
#   scripts/check-drive-root-litter.sh          scan this host's drive roots
#
# Exit: 0 clean, or a no-op on a non-Windows host; 1 litter found; 2 usage error.
#
# WHAT IT DETECTS AND WHY THAT SHAPE. Git Bash spells `D:\dir` as `/d/dir`.
# Handed to PowerShell, cmd, or a Windows-native interpreter, the leading `/`
# anchors to the root of the CURRENT DRIVE, so the literal resolves to
# `<current-drive>:\d\dir` and the consumer creates that whole phantom chain
# before writing. The residue is therefore always the same shape: `<drive>:\<x>\`
# where `<x>` is the single letter of the drive the author MEANT to write to.
# `docs/conventions/windows-path-emit/README.md` owns the rule that prevents it;
# this script is that rule's detection net, for the runs that ignore it.
#
# Requiring the directory name to match a MOUNTED DRIVE is what keeps the
# detector precise. A single-letter directory is not suspicious on its own -
# `D:\a` is the workspace root on a GitHub-hosted Windows runner, and any number
# of projects use a one-character top-level folder deliberately. It becomes the
# fingerprint of THIS defect only when that letter also names a real drive on the
# same host, because that is the coincidence the mechanism requires: the phantom
# path is built from a drive letter the author spelled out. #2594 asked for a
# drive-root guard against an EXTERNAL writer's `C:\tmp` residue (now
# plugins/guardrails/hooks/block-windows-drive-tmp.sh, a PreToolUse guard on the
# command string); this is the same concern pointed at a producer we own, and it
# looks at the filesystem AFTER a run rather than at a command before it.
#
# ADVISORY BY DEFAULT, not wired into a required lane that scans a live machine.
# docs/adr/0003 is this repo's doctrine for that: a verification guard earns
# default-on by measured precision, and this detector has none yet. CI runs its
# self-test (deterministic, fixture-scoped) and asserts the non-Windows no-op;
# the live scan is an operator/harness-author command. Promote it when there is
# precision to point at.
#
# FIXTURE SEAM. `DRIVE_ROOT_LITTER_MOUNT_ROOT` relocates the MSYS mount root the
# scan reads (default `/`, where Git Bash mounts `C:` at `/c`). It is the one
# seam, it is opt-in, and it is never auto-detected - so a bare invocation on a
# CI runner is provably the host scan and nothing else. Drives are found by
# PROBING `<mount-root>/<letter>` with `-d` rather than by listing the mount
# root, because MSYS maps drives lazily: `ls /` shows no single-letter entries on
# a real Git Bash host even though `/c` and `/d` both resolve.
set -uo pipefail

if (($# > 0)); then
  echo "usage: check-drive-root-litter.sh    (no arguments)" >&2
  exit 2
fi

# Host gate, first and unconditional, so the bare invocation on a Linux or macOS
# runner cannot reach any filesystem probing at all. Non-Windows hosts have no
# drive letters, so this defect cannot occur and there is nothing to scan. The
# skip is REPORTED, never silent.
case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*)
  echo "check-drive-root-litter.sh: no-op on a non-Windows host (OSTYPE=${OSTYPE:-unset}); drive-root litter is a Windows-only shape."
  exit 0
  ;;
esac

mount_root="${DRIVE_ROOT_LITTER_MOUNT_ROOT:-/}"
mount_root="${mount_root%/}"

# The set of mounted drive letters. This is both the set of roots to scan AND
# the set of directory names that count as a hit.
drives=()
for letter in {a..z}; do
  [[ -d "$mount_root/$letter" ]] && drives+=("$letter")
done

if ((${#drives[@]} == 0)); then
  echo "check-drive-root-litter.sh: no drives found under '${mount_root:-/}'; nothing to scan."
  exit 0
fi

# A candidate that CONTAINS the current working directory is a real checkout
# location, not litter: someone whose repo lives at `D:\c\work\repo` would
# otherwise be told their own checkout is residue. Both sides are compared in
# PHYSICAL form, because MSYS mount aliases make the lexical spellings differ
# for the same directory (`/tmp/x` and `/c/Users/.../Temp/x` are one place).
here="$(pwd -P 2>/dev/null)" || here="$(pwd)"

hits=()
for drive in "${drives[@]}"; do
  for name in "${drives[@]}"; do
    candidate="$mount_root/$drive/$name"
    [[ -d "$candidate" ]] || continue
    cand_real="$(cd "$candidate" 2>/dev/null && pwd -P)"
    [[ -n "$cand_real" ]] || cand_real="$candidate"
    case "$here/" in
    "$cand_real"/*) continue ;;
    *) ;; # the cwd is elsewhere: the candidate is a real hit
    esac
    if [[ "$mount_root" == "" ]]; then
      hits+=("$candidate    (${drive^}:\\${name}\\)")
    else
      hits+=("$candidate")
    fi
  done
done

if ((${#hits[@]} == 0)); then
  echo "check-drive-root-litter.sh: ${#drives[@]} drive root(s) scanned under '${mount_root:-/}'; no drive-root litter found."
  exit 0
fi

echo "check-drive-root-litter.sh: drive-root litter found (${#hits[@]}):" >&2
for hit in "${hits[@]}"; do
  echo "  $hit" >&2
done
cat >&2 <<'EOF'

Each path above is a directory at a drive root named for another mounted drive -
the fingerprint of an MSYS path literal (/d/...) handed to a Windows-native
consumer, which resolved it against the CURRENT drive's root instead.

The litter is the cheap part. Whatever wrote it wrote to a path it did not
intend, so any run that produced it may have measured something other than what
it claims. Re-check the run's results before trusting them, then:

  * fix the emitter - see docs/conventions/windows-path-emit/README.md, and
    scripts/emit-windows-path.sh for the conversion itself;
  * remove the phantom tree once you have confirmed it holds nothing else.
EOF
exit 1
