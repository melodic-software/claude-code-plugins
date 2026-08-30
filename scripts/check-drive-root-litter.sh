#!/usr/bin/env bash
# Detect the on-disk fingerprint of an unconverted POSIX path handed to a
# Windows-native consumer. Two classes share the mechanism:
#   * a directory at a drive root whose name is a single letter that is ITSELF
#     a mounted drive (an MSYS /d/... literal), and
#   * a directory at a drive root carrying a KNOWN TEMP-SINK NAME (a POSIX
#     /tmp literal), e.g. C:\tmp.
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
# The TEMP-SINK class is the same mechanism with the literal spelled `/tmp`
# instead of `/<drive>/...`: Git Bash's real temp is a mount
# (`/tmp` -> `%TEMP%`), but a Windows-native consumer given the literal
# resolves it to `<current-drive>:\tmp` and creates it. The name vocabulary is
# deliberately the sibling guard's: `tmp` is the only drive-root sink
# block-windows-drive-tmp.sh blocks (`/var/tmp` and `%TEMP%` are legitimate and
# never sit at a volume root), so `tmp` is the only name here. Grow both lists
# together. Precision comes from the name being a sink nothing legitimately
# roots at a volume top on Windows - unlike the single-letter class there is no
# mounted-drive coincidence to require, so this class carries an opt-out:
# DRIVE_ROOT_LITTER_IGNORE_SINKS (space- or comma-separated names) exempts an
# operator who keeps a deliberate `C:\tmp`. Sink names match CASE-INSENSITIVELY
# in both directions - Windows filesystems are case-insensitive, so `C:\TMP`
# and `C:\tmp` are one directory, and the detector enumerates drive-root
# entries rather than probing the literal lowercase name so the contract holds
# on the case-sensitive filesystems the test fixtures run on; the opt-out
# accepts any casing for the same reason. An env var rather than a marker
# file inside the directory, because the detector cannot trust litter's own
# contents to prove intent, and the env var keeps the exemption visible at the
# invocation site. The single-letter class has no opt-out and is unaffected.
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
# the set of directory names that count as a single-letter-class hit.
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

# Shared candidate check for both classes: skip a non-directory, skip a
# candidate that contains the cwd (a real checkout location, not litter - see
# the comment above `here`), record everything else as a hit.
record_if_litter() {
  local drive="$1" name="$2" candidate cand_real
  candidate="$mount_root/$drive/$name"
  [[ -d "$candidate" ]] || return 0
  cand_real="$(cd "$candidate" 2>/dev/null && pwd -P)"
  [[ -n "$cand_real" ]] || cand_real="$candidate"
  case "$here/" in
  "$cand_real"/*) return 0 ;;
  *) ;; # the cwd is elsewhere: the candidate is a real hit
  esac
  if [[ "$mount_root" == "" ]]; then
    hits+=("$candidate    (${drive^}:\\${name}\\)")
  else
    hits+=("$candidate")
  fi
}

# Single-letter class: a drive-root directory named for another mounted drive.
for drive in "${drives[@]}"; do
  for name in "${drives[@]}"; do
    record_if_litter "$drive" "$name"
  done
done

# Temp-sink class (see the header): a known sink name at a drive root, matched
# case-insensitively by ENUMERATING the drive root's entries - a lowercase
# probe would rely on the host filesystem folding case, which the test
# fixtures' filesystems do not. DRIVE_ROOT_LITTER_IGNORE_SINKS exempts a name,
# any casing.
sink_names=" tmp "
ignored_sinks="${DRIVE_ROOT_LITTER_IGNORE_SINKS:-}"
ignored_sinks="${ignored_sinks//,/ }"
ignored_sinks=" ${ignored_sinks,,} "
for drive in "${drives[@]}"; do
  for entry in "$mount_root/$drive"/*/; do
    [[ -d "$entry" ]] || continue
    name="${entry%/}"
    name="${name##*/}"
    name_lc="${name,,}"
    [[ "$sink_names" == *" $name_lc "* ]] || continue
    [[ "$ignored_sinks" == *" $name_lc "* ]] && continue
    record_if_litter "$drive" "$name"
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

Each path above carries this defect's fingerprint at a drive root: a directory
named for another mounted drive (an MSYS /d/... literal) or a known temp-sink
name such as tmp (a POSIX /tmp literal). Either way, a POSIX path was handed to
a Windows-native consumer, which resolved it against the CURRENT drive's root
instead of the intended location.

The litter is the cheap part. Whatever wrote it wrote to a path it did not
intend, so any run that produced it may have measured something other than what
it claims. Re-check the run's results before trusting them, then:

  * fix the emitter - see docs/conventions/windows-path-emit/README.md, and
    scripts/emit-windows-path.sh for the conversion itself;
  * CHECK FOR A REGISTERED GIT WORKTREE BEFORE REMOVING ANYTHING. A phantom
    tree can contain one: a `git worktree add` given an unconverted path
    registers the worktree in the parent repository, so the directory is live
    state and not merely residue. Look for a `.git` FILE (not directory) whose
    contents read `gitdir: <repo>/.git/worktrees/<name>`; that names the parent
    repository. Deregister with `git -C <parent-repo> worktree remove --force
    <path>` - which removes the directory too - rather than deleting the
    directory first, which strands the registry entry and leaves `git worktree
    prune` as the only cleanup, on a repository whose other entries may belong
    to live lanes;
  * remove the phantom tree once you have confirmed it holds nothing else and
    nothing in it is registered.
EOF
exit 1
