#!/usr/bin/env bash
# Count what one registered hooks.json command costs per fire, at the kernel.
#
#   scripts/hook-census.sh <plugin> <event> <row> <payload> [options]
#
#   <row>      fixed text the handler's `command` contains. The first handler
#              under <event> in plugins/<plugin>/hooks/hooks.json whose command
#              contains it is the one run, as registered: `sh -c <command>`, the
#              shell the hooks docs name for a shell-form command on Linux.
#   <payload>  the stdin JSON. `@DIR@` becomes the scratch repository (the
#              fire's cwd and CLAUDE_PROJECT_DIR), `@TRANSCRIPT@` the generated
#              transcript.
#
#   --measure spawns            (default) process creations plus successful
#                               execve calls, the hook's own `sh` included
#   --measure transcript-bytes  bytes read from the transcript by any process
#   --measure growth            transcript bytes at 10 MiB minus at 50 KiB,
#                               floored at 0: a hook whose per-fire read does
#                               not grow with the transcript prints 0
#   --transcript-bytes N        generate a deterministic JSONL transcript of
#                               whole lines, at most N bytes
#   --seed                      fire once untraced first, then append one line
#                               to the transcript, so the measured fire takes
#                               the warm path a later turn takes
#   --env K=V                   extra environment for every fire (repeatable)
#   --setup CMD                 run in the scratch repository before any fire
#   --check CMD                 run there after the measured fire; it asserts
#                               the path taken. $HOOK_STDOUT holds its stdout.
#
#   scripts/hook-census.sh --versions
#                               print the versions of the programs a count
#                               depends on, for reading an ABOVE after a
#                               runner image change
#
# Every fire runs under `env -i` with a fresh HOME, TMPDIR, CLAUDE_PLUGIN_DATA
# and scratch git repository, all removed on exit, plus LC_ALL=C and no system
# git config, so nothing the host carries moves the count except the programs
# on PATH. Those are what --versions names. strace follows descriptors under
# -P, so a builtin read (`mapfile <"$t"`) is counted the same as `cat "$t"`; a
# spawn counter cannot see that class (#4408).
#
# The fire is not network-sandboxed, and CLAUDE_PLUGIN_ROOT is this checkout:
# the ubuntu-24.04 runner refuses `unshare -rn` (write to /proc/self/uid_map
# not permitted). A payload must steer the hook down a path that neither
# reaches the network nor writes under its plugin root.
#
# Exit: 0 measured; 2 cannot measure (bad arguments, no strace, jq or git, no
# such row, --setup failed); 3 the fire exited nonzero, --check failed, or a
# growth fire read no transcript byte at either size.
set -euo pipefail

usage() {
  sed -n '2,/^set -euo/{/^#/!d;s/^# \{0,1\}//;p}' "$0" >&2
  exit 2
}

# first_line <program> <args...>: the first line the program prints, or the
# shell's error when it is missing.
first_line() {
  local out
  out="$("$@" 2>&1)" || :
  printf '%s' "${out%%$'\n'*}"
}
if [[ "${1:-}" == --versions ]]; then
  sh_path="$(readlink -f /bin/sh)"              # portability-ok: strace makes this script Linux-only
  awk_path="$(readlink -f "$(command -v awk)")" # portability-ok: strace makes this script Linux-only
  echo "hook-census versions: bash=${BASH_VERSION}" \
    "sh=$sh_path" \
    "git=$(first_line git --version)" \
    "jq=$(first_line jq --version)" \
    "strace=$(first_line strace -V)" \
    "python3=$(first_line python3 --version)" \
    "coreutils=$(first_line env --version)" \
    "grep=$(first_line grep --version)" \
    "sed=$(first_line sed --version)" \
    "awk=$awk_path"
  exit 0
fi

(($# >= 4)) || usage
PLUGIN="$1" EVENT="$2" ROW="$3" PAYLOAD="$4"
shift 4
MEASURE=spawns BYTES=0 SEED=0 SETUP="" CHECK=""
EXTRA_ENV=()
while (($#)); do
  case "$1" in
  --measure) MEASURE="${2:-}" ;;
  --transcript-bytes) BYTES="${2:-}" ;;
  --env) EXTRA_ENV+=("${2:-}") ;;
  --setup) SETUP="${2:-}" ;;
  --check) CHECK="${2:-}" ;;
  --seed)
    SEED=1
    shift
    continue
    ;;
  *) usage ;;
  esac
  (($# >= 2)) || usage
  shift 2
done
[[ "$MEASURE" =~ ^(spawns|transcript-bytes|growth)$ && "$BYTES" =~ ^[0-9]+$ ]] || usage

for tool in strace jq git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "hook-census: $tool is required and not on PATH" >&2
    exit 2
  }
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$REPO/plugins/$PLUGIN"
HOOKS_JSON="$ROOT/hooks/hooks.json"
[[ -f "$HOOKS_JSON" ]] || {
  echo "hook-census: no $HOOKS_JSON" >&2
  exit 2
}
COMMAND="$(jq -r --arg e "$EVENT" --arg r "$ROW" \
  'first(.hooks[$e][]?.hooks[]? | .command | select(type == "string" and contains($r))) // empty' \
  "$HOOKS_JSON")"
[[ -n "$COMMAND" ]] || {
  echo "hook-census: no $EVENT handler in $HOOKS_JSON has a command containing: $ROW" >&2
  exit 2
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# One assistant record, repeated. Whole lines only, so a reader that parses
# JSONL sees a valid transcript at any size.
LINE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"The census transcript line is fixed text so every run reads the same bytes."}]},"uuid":"census","session_id":"census"}'

# census_once <transcript-bytes> <spawns|transcript-bytes>: prints the count.
census_once() {
  local bytes="$1" mode="$2" run
  run="$(mktemp -d "$WORK/run.XXXXXX")"
  local dir="$run/repo" transcript="$run/transcript.jsonl"
  mkdir -p "$dir" "$run/home" "$run/tmp" "$run/data"
  git init -q "$dir"
  : >"$transcript"
  if ((bytes > 0)); then
    awk -v n="$((bytes / (${#LINE} + 1)))" -v l="$LINE" 'BEGIN { for (i = 0; i < n; i++) print l }' >"$transcript"
  fi
  local payload="${PAYLOAD//@DIR@/$dir}"
  payload="${payload//@TRANSCRIPT@/$transcript}"
  printf '%s' "$payload" >"$run/payload.json"

  local env_args=(
    PATH="$PATH" HOME="$run/home" TMPDIR="$run/tmp" LC_ALL=C GIT_CONFIG_NOSYSTEM=1
    CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$run/data" CLAUDE_PROJECT_DIR="$dir"
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}
  )
  if [[ -n "$SETUP" ]]; then
    (cd "$dir" && env -i "${env_args[@]}" bash -c "$SETUP") >&2 || {
      echo "hook-census: --setup failed" >&2
      exit 2
    }
  fi
  if ((SEED)); then
    (cd "$dir" && env -i "${env_args[@]}" sh -c "$COMMAND" <"$run/payload.json" >/dev/null 2>&1) || :
    ((bytes == 0)) || printf '%s\n' "$LINE" >>"$transcript"
  fi

  local trace=(-e "trace=clone,clone3,fork,vfork,execve")
  [[ "$mode" == spawns ]] ||
    trace=(-P "$transcript" -e "trace=read,pread64,readv,preadv,preadv2,sendfile,copy_file_range,splice")
  local rc=0
  (cd "$dir" && env -i "${env_args[@]}" \
    strace -ff -qq -s 400 -e signal=none "${trace[@]}" -o "$run/trace" \
    sh -c "$COMMAND" <"$run/payload.json" >"$run/stdout" 2>"$run/stderr") || rc=$?
  if ((rc != 0)); then
    echo "hook-census: the fire exited $rc; stderr: $(head -c 2000 "$run/stderr")" >&2
    exit 3
  fi
  if [[ -n "$CHECK" ]]; then
    (cd "$dir" && env -i "${env_args[@]}" HOOK_STDOUT="$run/stdout" bash -c "$CHECK") >&2 || {
      echo "hook-census: --check failed; stdout: $(head -c 2000 "$run/stdout")" >&2
      exit 3
    }
  fi

  # -ff writes one file per pid, so a call and its result share a line.
  if [[ "$mode" == spawns ]]; then
    local creations execs
    creations="$(cat "$run"/trace.* | grep -E '^(clone|clone3|fork|vfork)\(' | grep -v CLONE_THREAD | grep -cE '= [0-9]+$' || :)"
    execs="$(cat "$run"/trace.* | grep -cE '^execve\(.*= 0$' || :)"
    echo "$((creations + execs)) creations=$creations execs=$execs"
  else
    cat "$run"/trace.* | awk '/= [0-9]+$/ { n += $NF } END { print n + 0 }'
  fi
}

if [[ "$MEASURE" != growth ]]; then
  out="$(census_once "$BYTES" "$MEASURE")"
  label=spawns
  [[ "$MEASURE" == spawns ]] || label=bytes
  echo "$label=$out"
  exit 0
fi
small="$(census_once 51200 transcript-bytes)"
large="$(census_once 10485760 transcript-bytes)"
# A hook that read nothing at either size never reached its reader: flat, and
# proving nothing.
((small + large > 0)) || {
  echo "hook-census: no transcript byte was read at either size" >&2
  exit 3
}
growth=$((large - small))
((growth > 0)) || growth=0
echo "growth=$growth small=$small large=$large"
