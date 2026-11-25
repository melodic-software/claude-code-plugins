#!/usr/bin/env bash

port_status() {
  local port="$1"
  if command -v curl >/dev/null 2>&1; then
    local rc=0
    curl --noproxy '*' -sS --max-time 2 -o /dev/null "http://127.0.0.1:${port}" 2>/dev/null || rc=$?
    case "$rc" in
      0 | 1 | 8 | 52 | 56) printf 'listening\n' ;;
      *) printf 'free\n' ;;
    esac
    return 0
  fi
  if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
    exec 3>&- 3<&-
    printf 'listening\n'
    return 0
  fi
  printf 'free\n'
  return 0
}
