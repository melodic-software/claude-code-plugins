#!/usr/bin/env bash
# start-collector.sh — idempotent ensure-running for the local Claude Code OTEL Collector.
#
# Resolves an absolute store dir (CC_OTEL_STORE, else <repo-root>/.claude/observability/otel),
# creates it, locates the otelcol-contrib binary, and — only if 127.0.0.1:4318 is not already
# bound — spawns the Collector detached with otel-collector.yaml alongside this script.
#
# NON-BLOCKING / advisory: every non-happy path (binary absent, spawn skipped) exits 0 so a
# SessionStart hook backstop never blocks session start. The Collector is a machine singleton —
# a second invocation no-ops when :4318 is already bound (the OS rejects a duplicate port bind).
#
# Worktree-safety note: a true machine-singleton store requires CC_OTEL_STORE set as an OS user
# env var (so the Collector spawn AND every duckdb query — in any worktree — resolve the same
# absolute path). When CC_OTEL_STORE is unset, this script spawns the
# Collector with CWD = repo root so the otel-collector.yaml relative fallback resolves to the
# repo-root store, matching a duckdb query run (also unset) from the repo root.
#
# Usage:
#   bash start-collector.sh            # ensure running (spawn if down)
#   bash start-collector.sh --dry-run  # resolve + report, never spawn
#   bash start-collector.sh --help
#
# Env overrides:
#   CC_OTEL_STORE  absolute store dir (default: <repo-root>/.claude/observability/otel)
#   CC_OTEL_BIN    otelcol-contrib binary path (default: PATH, then ~/.otelcol/ probe)

set -euo pipefail

readonly OTLP_HTTP_PORT=4318
readonly OTLP_GRPC_PORT=4317
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=net-probe.sh
source "$SCRIPT_DIR/net-probe.sh"

usage() {
  cat <<'EOF'
Usage: start-collector.sh [--dry-run] [--help]

Idempotent ensure-running for the local Claude Code OTEL Collector.
Spawns otelcol-contrib (detached) with otel-collector.yaml alongside this script
only when 127.0.0.1:4318 is not already bound. Advisory: always exits 0 on the
spawn/skip paths so a SessionStart hook never blocks session start.

Options:
  --dry-run   Resolve store dir + binary + port status and report; never spawn.
  --help      Show this help.

Env:
  CC_OTEL_STORE   absolute store dir (default: <repo-root>/.claude/observability/otel)
  CC_OTEL_BIN     otelcol-contrib binary path (default: PATH, then ~/.otelcol/ probe)
EOF
}

# Resolve the consumer project root: CLAUDE_PROJECT_DIR when the harness sets
# it, else the git worktree containing the CWD, else the CWD. Never the script's
# own location — under plugin cache isolation that is not the project.
# Always returns 0 — prints the resolved absolute path.
resolve_repo_root() {
  local root
  root="${CLAUDE_PROJECT_DIR:-}"
  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ -z "$root" ]]; then
    root="$(pwd)"
  fi
  printf '%s\n' "$root"
}

# Locate otelcol-contrib. Precedence: explicit CC_OTEL_BIN override > PATH > ~/.otelcol/ probe.
# Always returns 0 — prints the binary path, or the literal NOT_FOUND when unresolvable. (Returns
# 0 even when unresolvable so callers capture via $() outside an if — keeps set -e effective,
# avoids ShellCheck SC2310 set-e-suppressed-in-condition.)
resolve_bin() {
  if [[ -n "${CC_OTEL_BIN:-}" && -x "${CC_OTEL_BIN}" ]]; then
    printf '%s\n' "${CC_OTEL_BIN}"
    return 0
  fi
  if command -v otelcol-contrib >/dev/null 2>&1; then
    command -v otelcol-contrib
    return 0
  fi
  local probe
  for probe in "$HOME/.otelcol/otelcol-contrib" "$HOME/.otelcol/otelcol-contrib.exe"; do
    if [[ -x "$probe" ]]; then
      printf '%s\n' "$probe"
      return 0
    fi
  done
  printf '%s\n' "NOT_FOUND"
  return 0
}

main() {
  local dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --help | -h)
        usage
        return 0
        ;;
      *)
        printf 'start-collector.sh: unknown argument %q\n\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
    shift
  done

  local repo_root store_dir config bin_status port_state grpc_port_state action sentinel
  repo_root="$(resolve_repo_root)"
  store_dir="${CC_OTEL_STORE:-$repo_root/.claude/observability/otel}"
  config="$SCRIPT_DIR/otel-collector.yaml"
  sentinel="$store_dir/.prune-in-progress"
  bin_status="$(resolve_bin)"
  port_state="$(port_status "$OTLP_HTTP_PORT")"
  grpc_port_state="$(port_status "$OTLP_GRPC_PORT")"

  # prune-otel-store.sh stops the Collector to trim the store and holds an mkdir-atomic
  # sentinel (.prune-in-progress) for the duration. Refuse to respawn while it exists — a
  # respawn would reopen the file the prune is rewriting (the revival race). The prune
  # removes the sentinel and restarts the Collector itself when done.
  #
  # The config binds BOTH receivers (:4318 http, :4317 gRPC). :4318 listening means the
  # Collector is presumed up (noop); :4318 free but :4317 taken means a foreign process
  # owns the gRPC port and a spawn would die on its duplicate bind — skip and say so.
  if [[ -d "$sentinel" ]]; then
    action="skip-prune-in-progress"
  elif [[ "$port_state" == "listening" ]]; then
    action="noop-already-running"
  elif [[ "$bin_status" == "NOT_FOUND" ]]; then
    action="skip-binary-absent"
  elif [[ "$grpc_port_state" == "listening" ]]; then
    action="skip-grpc-port-in-use"
  else
    action="would-spawn"
  fi

  printf 'store_dir=%s\n' "$store_dir"
  printf 'config=%s\n' "$config"
  printf 'binary=%s\n' "$bin_status"
  printf 'port_%s=%s\n' "$OTLP_HTTP_PORT" "$port_state"
  printf 'port_%s=%s\n' "$OTLP_GRPC_PORT" "$grpc_port_state"
  printf 'action=%s\n' "$action"

  if [[ "$dry_run" == true ]]; then
    return 0
  fi

  case "$action" in
    noop-already-running)
      return 0
      ;;
    skip-prune-in-progress)
      printf 'start-collector.sh: prune in progress (%s) — not spawning. ' "$sentinel" >&2
      printf 'prune-otel-store.sh restarts the Collector when done.\n' >&2
      return 0
      ;;
    skip-binary-absent)
      printf 'start-collector.sh: otelcol-contrib not found (PATH / CC_OTEL_BIN / ~/.otelcol). ' >&2
      printf 'Telemetry capture is OFF until installed. Continuing (advisory).\n' >&2
      return 0
      ;;
    skip-grpc-port-in-use)
      printf 'start-collector.sh: :%s is free but :%s is taken by another process — ' "$OTLP_HTTP_PORT" "$OTLP_GRPC_PORT" >&2
      printf 'a spawn would die on the gRPC duplicate bind. Telemetry capture is OFF. Continuing (advisory).\n' >&2
      return 0
      ;;
    would-spawn)
      # Re-check the prune sentinel closest to the spawn — minimizes the decision->spawn TOCTOU
      # (a prune that started after the action decision above must still suppress this spawn).
      if [[ -d "$sentinel" ]]; then
        printf 'start-collector.sh: prune started mid-decision (%s) — not spawning.\n' "$sentinel" >&2
        return 0
      fi
      mkdir -p "$store_dir"
      # Spawn detached from the repo root: keeps the yaml relative-store fallback correct when
      # CC_OTEL_STORE is unset; harmless when it is set (the yaml uses the absolute path). nohup
      # + redirected stdio + </dev/null detach the daemon so it outlives this script (and the
      # SessionStart hook that may invoke it).
      (
        cd "$repo_root" || exit 1
        nohup "$bin_status" --config "$config" </dev/null >"$store_dir/collector.log" 2>&1 &
      )
      printf 'start-collector.sh: spawned Collector (%s) -> %s\n' "$bin_status" "$store_dir" >&2
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

main "$@"
