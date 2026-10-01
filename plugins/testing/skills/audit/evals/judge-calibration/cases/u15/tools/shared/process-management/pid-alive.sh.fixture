#!/usr/bin/env bash
# Cross-platform process-liveness check for tools/ scripts.
#
# Consumers derive on demand via the repo dep-graph edge scan
# (tools/AGENTS.md "Vertical slices" — dep-graph row).
#
# Library — NOT executable. Pure-function: no env reads, no stdin parsing,
# no exit calls.
#
# WHY this exists (not just bare `kill -0`): on Git Bash / MSYS2, native
# Windows processes (the Node broker, `gh.exe` spawned outside the MSYS pid
# namespace) carry Windows PIDs that MSYS `kill -0` CANNOT see — it returns
# non-zero on a process that is demonstrably alive. Reconcile logic that reads
# "kill -0 failed" as "dead PID" then deletes a LIVE broker's discovery files,
# deadlocking channel mode (live broker holds the lock, but no port file points
# to it, so every new broker exits "another broker already running" and the
# subscriber can never rediscover it). Empirically reproduced 2026-05-29: a
# Git Bash `kill -0` reported DEAD on 5 broker PIDs that Windows `tasklist`
# confirmed alive. This helper falls back to a Windows-native `tasklist` query
# when `kill -0` fails on a Windows shell, so a live native-Windows PID is
# correctly reported alive. On Linux/macOS the `kill -0` result is authoritative
# and the fallback never runs.

# pid::is_alive <pid>
#
# Returns 0 when the process is alive, 1 otherwise (including non-numeric or
# empty input — a malformed PID is never "alive"). Never signals the process;
# `kill -0` only probes existence/permission.
#
# Args:
#   <pid>   process id to probe. Non-numeric / empty → 1 (not alive).
#
# Resolution order:
#   1. `kill -0 <pid>`            — authoritative on Linux/macOS + MSYS pids
#   2. Windows `tasklist` lookup  — only when (1) fails AND OS=Windows_NT AND
#                                   tasklist is on PATH (native-winpid fallback)

# Include guard — sourced by several tools (broker-prune, channel-gate,
# broker-supervisor, pid-graceful-stop, stop-github-watcher); sourcing twice is
# a no-op (matches broker-prune.sh).
[[ -n "${_PID_ALIVE_SH:-}" ]] && return 0
_PID_ALIVE_SH=1

pid::is_alive() {
  local pid="$1"

  # A malformed PID must never reach kill/tasklist. Digits-only guard mirrors
  # broker-prune.sh + the channel-gate watcher-pid guard.
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1

  # Primary: POSIX signal-0. Works for MSYS pids, Linux, macOS.
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi

  # Windows fallback: kill -0 cannot see native Windows PIDs from Git Bash.
  # tasklist is the authoritative Windows process query. `//FI` etc. use the
  # MSYS double-slash escape so the path-converter leaves the flags as `/FI`.
  # CSV row for a live PID contains the quoted pid field ("12345"); the
  # no-match output ("INFO: No tasks ...") does not, so a quoted-pid grep is a
  # precise liveness test.
  if [[ "${OS:-}" == "Windows_NT" ]] && command -v tasklist >/dev/null 2>&1; then
    tasklist //FI "PID eq ${pid}" //NH //FO CSV 2>/dev/null | grep -q "\"${pid}\""
    return $?
  fi

  return 1
}
