#!/usr/bin/env bash
# tools/github-events/stop-webhook-broker.sh — Send SIGINT to the running github-events broker.
#
# Reads the broker's PID file from the stable state directory
# (%LOCALAPPDATA%/github-events/ on Windows, $XDG_STATE_HOME/github-events/ elsewhere),
# sends SIGINT, waits up to 5s for graceful shutdown, escalates to SIGKILL if
# the process is still alive. The broker's own SIGINT handler removes the
# PID file; this script falls back to manual cleanup on SIGKILL escalation.
#
# Usage:
#   tools/github-events/stop-webhook-broker.sh
#   tools/github-events/stop-webhook-broker.sh --force      # skip SIGINT, go straight to SIGKILL
#
# Env overrides:
#   GITHUB_EVENTS_REPO        repo identity (owner/repo) the broker is keyed to
#                             (default: parsed from `git remote get-url origin`)
#   GITHUB_EVENTS_REPO_SLUG   override the sanitized repo slug directly (highest priority)
#   GITHUB_EVENTS_STATE_DIR   override the state directory
#
# Exit codes:
#   0  broker stopped cleanly OR no broker was running
#   2  broker process refused both SIGINT and SIGKILL
#   3  invalid argument

set -uo pipefail

# shellcheck source=../shared/process-management/pid-file-read.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/process-management/pid-file-read.sh"
# shellcheck source=../shared/process-management/pid-graceful-stop.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/process-management/pid-graceful-stop.sh"
# shellcheck source=../shared/process-management/pid-alive.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/process-management/pid-alive.sh"
# shellcheck source=state-paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/state-paths.sh"

FORCE=0
case "${1:-}" in
  --force) FORCE=1 ;;
  -h | --help)
    sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *)
    printf 'stop-webhook-broker: unknown argument %q (use --help)\n' "$1" >&2
    exit 3
    ;;
esac

# Resolve state paths via the shared SSOT lib (mirrors start-github-watcher.sh +
# stop-github-watcher.sh + channel-gate.sh; env.ts agrees byte-for-byte). One source
# for slug + STATE_DIR derivation so this stop path can never drift from the daemon's.
# The slug is the REPO IDENTITY (owner/repo), so a broker started from any worktree of
# this repo is found from any other. resolve_state_paths always yields a slug (the
# unknown-repo sentinel on a no-identity checkout), so there is no derive-failure path.
ghe::resolve_state_paths
STATE_DIR="$GHE_STATE_DIR"
SLUG="$GHE_REPO_SLUG"
PID_FILE="${STATE_DIR}/broker-${SLUG}.pid"

if [[ ! -f "$PID_FILE" ]]; then
  printf 'No broker PID file at %s — nothing to stop.\n' "$PID_FILE"
  exit 0
fi

PID=$(pid_file::read "$PID_FILE")
if [[ -z "$PID" ]]; then
  printf 'PID file %s is empty — removing.\n' "$PID_FILE" >&2
  rm -f "$PID_FILE"
  exit 0
fi

if ! pid::is_alive "$PID"; then
  printf 'PID %s in %s is not alive — cleaning up stale state.\n' "$PID" "$PID_FILE" >&2
  rm -f "$PID_FILE"
  exit 0
fi

# Defend against PID reuse: a crashed broker leaves a stale PID file, and the
# kernel may reassign that PID to an unrelated process before this script runs.
# pid::is_alive only proves the PID exists; it does not prove it is OUR broker.
#
# A `comm == node` check is too loose — many node-based tools (npm, MCP servers,
# vite, ts-node, claude code itself) would match. Verify the FULL command line
# includes our broker entry `build/broker/index.js` via POSIX `ps -p <pid> -o
# args=` (works on Linux, macOS, and Git Bash on Windows). The path separator may
# be `/` (Linux/macOS) or `\` (Git Bash) depending on how Node was invoked, so
# match both.
#
# Substring match, no leading-separator requirement: the documented launch paths
# (`tools/github-events/start-webhook-broker.sh`, subscriber auto-spawn) use
# absolute paths, but `npm run start:broker` invokes `node build/broker/index.js`
# from the package directory — a relative path with no separator before `build`.
# Requiring a leading `/` or `\` would misclassify that live broker as PID reuse
# and remove its state files without signaling. PID reuse onto an unrelated
# process whose args happen to contain `build/broker/index.js` is implausible
# enough that the cost of a stray SIGINT is lower than the cost of an unmanaged
# broker.
#
# If `ps` fails or returns no recognizable broker entry, treat the PID file as
# stale and clean up without signaling — kills of unrelated processes are far
# more disruptive than a stranded lock dir.
PROCESS_ARGS=$(ps -p "$PID" -o args= 2>/dev/null | tr -d '\r')
case "$PROCESS_ARGS" in
  *build/broker/index.js* | *'build\broker\index.js'*) ;;
  *)
    printf 'PID %s does not appear to be our broker (args: %q) — assuming PID reuse, cleaning up stale state.\n' \
      "$PID" "$PROCESS_ARGS" >&2
    rm -f "$PID_FILE"
    exit 0
    ;;
esac

printf 'Stopping broker (PID %s) ...\n' "$PID"

cleanup_state() {
  rm -f "$PID_FILE"
  rm -f "${STATE_DIR}/broker-${SLUG}.ports.json"
}

if [[ $FORCE -eq 0 ]]; then
  pid::graceful_stop "$PID" INT 50 0.1
  case $? in
    0)
      printf '  exited cleanly.\n'
      cleanup_state
      exit 0
      ;;
    1)
      printf '  did not exit within 5s; killed via SIGKILL.\n' >&2
      cleanup_state
      exit 0
      ;;
    *)
      printf 'ERROR: broker (PID %s) still alive after SIGKILL.\n' "$PID" >&2
      exit 2
      ;;
  esac
fi

# --force path: skip SIGINT, signal SIGKILL directly. Zero poll attempts make
# pid::graceful_stop send SIGKILL immediately, then confirm death via the
# winpid-aware pid::is_alive poll (rc 1 = killed, rc 2 = still alive).
pid::graceful_stop "$PID" KILL 0 0.1
case $? in
  2)
    printf 'ERROR: broker (PID %s) still alive after SIGKILL.\n' "$PID" >&2
    exit 2
    ;;
  *)
    cleanup_state
    printf '  killed.\n'
    exit 0
    ;;
esac
