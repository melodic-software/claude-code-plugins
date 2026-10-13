#!/usr/bin/env bash
# Decide whether a feature-map refresh pass has work to do, and record a clean
# pass. Runs git only.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: upkeep-skip.sh check  --repo <dir> --map <repo-relative path> --state-dir <dir> [--since <N>h|<N>d]
       upkeep-skip.sh record --repo <dir> --map <repo-relative path> --state-dir <dir>
       upkeep-skip.sh --help

check   prints one line, "run <reason>" or "skip <reason>", and exits 0.
        A stored SHA equal to HEAD skips; a different one runs. With no stored
        state, a HEAD committed longer ago than --since (default 24h) skips.
        Reads git and the state file only.
record  stores HEAD's SHA as the last clean pass for this repository and map,
        in <state-dir>/feature-map-upkeep/<hash of repository and map path>.

Exit: 0 decided or recorded, 2 bad arguments, missing repository or
unwritable state directory (nothing on stdout).
EOF
}

die() {
  printf 'upkeep-skip: %s\n' "$1" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
-h | --help)
  usage
  exit 0
  ;;
check | record) shift ;;
*) die "unknown subcommand '${cmd}' (want check, record or --help)" ;;
esac

repo='' map='' state_dir='' since=24h
while (($# > 0)); do
  case "$1" in
  --repo | --map | --state-dir | --since)
    (($# >= 2)) || die "$1 needs a value"
    case "$1" in
    --repo) repo="$2" ;;
    --map) map="$2" ;;
    --state-dir) state_dir="$2" ;;
    --since)
      [[ "$cmd" == check ]] || die "--since applies to check only"
      since="$2"
      ;;
    *) ;;
    esac
    shift 2
    ;;
  *) die "unknown argument '$1'" ;;
  esac
done

[[ -n "$repo" ]] || die "--repo is required"
[[ -n "$state_dir" ]] || die "--state-dir is required"
[[ -n "$map" ]] || die "--map is required"
case "$map" in
/* | \\* | ~* | [A-Za-z]:*) die "--map must be relative to the repository: '$map'" ;;
*..*) die "--map must not contain '..': '$map'" ;;
*) ;;
esac
[[ "$since" =~ ^[1-9][0-9]*[hd]$ ]] || die "--since must be <N>h or <N>d with N >= 1: '$since'"
while [[ "$map" == */ ]]; do map="${map%/}"; done

top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: '$repo'"
head_sha="$(git -C "$top" rev-parse --verify -q 'HEAD^{commit}')" || die "repository has no commit: '$top'"
key="$(printf '%s\n%s\n' "$top" "$map" | git -C "$top" hash-object --stdin)"
dir="$state_dir/feature-map-upkeep"
state_file="$dir/$key"

if [[ "$cmd" == record ]]; then
  mkdir -p -- "$dir" 2>/dev/null && [[ -w "$dir" ]] || die "state directory is not writable: '$dir'"
  tmp="$(mktemp "$dir/.tmp.XXXXXX")" || die "cannot create a file in '$dir'"
  if ! printf '%s\n' "$head_sha" >"$tmp" || ! mv -f -- "$tmp" "$state_file"; then
    rm -f -- "$tmp"
    die "cannot write '$state_file'"
  fi
  printf 'recorded %s\n' "$head_sha"
  exit 0
fi

if [[ -e "$state_dir" && ! (-d "$state_dir" && -w "$state_dir") ]]; then
  die "state directory is not writable: '$state_dir'"
fi
if [[ -f "$state_file" ]]; then
  stored="$(head -n 1 -- "$state_file")"
  if [[ "$stored" == "$head_sha" ]]; then
    printf 'skip unchanged since the last clean pass\n'
  else
    printf 'run HEAD moved since the last clean pass\n'
  fi
  exit 0
fi

committed="$(git -C "$top" log -1 --format=%ct HEAD)"
[[ "$committed" =~ ^[0-9]+$ ]] || die "unreadable commit time for HEAD: '$committed'"
now="$(date +%s)"
n="${since%?}"
unit=3600
[[ "$since" == *d ]] && unit=86400
# A count past nine digits is a window wider than any commit's age.
if ((${#n} <= 9 && now - committed > n * unit)); then
  printf 'skip no commit within %s and no state on this host\n' "$since"
else
  printf 'run commit within %s and no state on this host\n' "$since"
fi
