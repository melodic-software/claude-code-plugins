#!/usr/bin/env bash
# Exit: 0 clean, or a no-op on a non-Windows host; 1 litter found; 2 usage error.
set -uo pipefail

if (($# > 0)); then
  echo "usage: check-drive-root-litter.sh    (no arguments)" >&2
  exit 2
fi

case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*)
  echo "check-drive-root-litter.sh: no-op on a non-Windows host (OSTYPE=${OSTYPE:-unset}); drive-root litter is a Windows-only shape."
  exit 0
  ;;
esac

mount_root="${DRIVE_ROOT_LITTER_MOUNT_ROOT:-/}"
mount_root="${mount_root%/}"

drives=()
for letter in {a..z}; do
  [[ -d "$mount_root/$letter" ]] && drives+=("$letter")
done

if ((${#drives[@]} == 0)); then
  echo "check-drive-root-litter.sh: no drives found under '${mount_root:-/}'; nothing to scan."
  exit 0
fi

here="$(pwd -P 2>/dev/null)" || here="$(pwd)"

hits=()

record_if_litter() {
  local drive="$1" name="$2" candidate cand_real
  candidate="$mount_root/$drive/$name"
  [[ -d "$candidate" ]] || return 0
  cand_real="$(cd "$candidate" 2>/dev/null && pwd -P)"
  [[ -n "$cand_real" ]] || cand_real="$candidate"
  [[ "$here/" == "$cand_real"/* ]] && return 0
  if [[ -z "$mount_root" ]]; then
    hits+=("$candidate    (${drive^}:\\${name}\\)")
  else
    hits+=("$candidate")
  fi
}

for drive in "${drives[@]}"; do
  for name in "${drives[@]}"; do
    record_if_litter "$drive" "$name"
  done
done

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

  * fix the emitter - see docs/contracts/windows-path-emit/README.md, and
    scripts/emit-windows-path.sh for the conversion itself;
  * check for a registered git worktree before removing anything. A phantom
    tree can contain one: a `git worktree add` given an unconverted path
    registers the worktree in the parent repository, so the directory is live
    state and not merely residue. Look for a `.git` file (not directory) whose
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
