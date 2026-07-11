#!/usr/bin/env bash
# net-probe.sh — portable "is 127.0.0.1:<port> already bound?" probe.
# Sourced by start-collector.sh and start-dashboard.sh; not an entry point.
# Self-contained: defines port_status, requires nothing from the caller.

# Report whether something is already listening on 127.0.0.1:<port>.
# Always returns 0 — prints "listening" or "free".
#
# Why not bash /dev/tcp alone: net-redirection is compiled OUT on MSYS2/Git-Bash
# (the repo's primary Windows shell), where the raw probe ALWAYS fails and falsely
# reads "free" -> a doomed Collector/dashboard respawn every session. curl is the
# portable check (Git for Windows bundles it; near-universal on Linux/macOS), with
# bash net-redirection kept as the no-curl fallback (Linux/macOS/Cygwin).
# (bash/conventions.md "Known Git Bash quirks": No /dev/tcp -> use curl or nc.)
port_status() {
  local port="$1"
  if command -v curl >/dev/null 2>&1; then
    local rc=0
    # --noproxy '*': never route the localhost probe through http_proxy/HTTPS_PROXY
    # (commonly set in CI / corporate networks) — that would report the proxy's
    # reachability, not the local port's.
    #
    # Exit-code mapping: anything proving a TCP peer ACCEPTED the connection is
    # "listening" even when it does not speak HTTP — rc 0 (HTTP answer),
    # 1 (protocol mismatch, e.g. an SSH/HTTP-0.9-style banner; the scheme here
    # is a fixed http:// so rc 1 never means a bad URL), 8 (weird reply),
    # 52 (empty reply), 56 (recv failure after connect). A non-HTTP process on
    # the port must read as occupied, or callers publish a doomed bind onto it.
    # Remaining ambiguity (28 timeout, and anything else) leans "free" on
    # purpose: this is an advisory ensure-running, so a false "free" only
    # triggers a spurious spawn that loses the OS dup-bind race, whereas a
    # false "listening" would leave the daemon DOWN all session.
    curl --noproxy '*' -sS --max-time 2 -o /dev/null "http://127.0.0.1:${port}" 2>/dev/null || rc=$?
    case "$rc" in
      0 | 1 | 8 | 52 | 56) printf 'listening\n' ;;
      *) printf 'free\n' ;;
    esac
    return 0
  fi
  # No curl: bash net-redirection. A refused localhost connect returns at once.
  if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
    exec 3>&- 3<&-
    printf 'listening\n'
    return 0
  fi
  printf 'free\n'
  return 0
}
