#!/usr/bin/env bash
# start-dashboard.sh — idempotent ensure-running for a local OTEL Aspire dashboard container.
#
# Two roles (one container each), selected via --role:
#   cc   (default)  local-otel-dashboard-claude-code  UI :18888 / OTLP gRPC :18889 — Claude Code telemetry
#   apps            local-otel-dashboard-apps         UI :19888 / OTLP gRPC :19889 — app/default-route telemetry
#
# Spawns mcr.microsoft.com/dotnet/aspire-dashboard with a purpose-based name and the
# identification label set documented below.
# The Collector routes telemetry by resource service.name (see otel-collector.yaml):
# claude-code -> the cc dashboard; everything else (default route) -> the apps dashboard.
# All three signals (logs, metrics, traces) are forwarded to each. DuckDB file capture remains
# the persistent SSOT for CC telemetry — dashboards are in-memory live tails bounded by their
# built-in telemetry caps; restart resets them.
#
# NON-BLOCKING / advisory: skip paths (docker absent, aspire-dashboard container, port conflict) exit 0.
#
# Usage:
#   bash start-dashboard.sh [--role cc|apps]            # ensure running (start/spawn if down)
#   bash start-dashboard.sh [--role cc|apps] --dry-run  # resolve + report, never spawn
#   bash start-dashboard.sh --help
#
# Env overrides:
#   CC_OTEL_DASHBOARD_IMAGE          image ref (default: mcr.microsoft.com/dotnet/aspire-dashboard:13.4.2)
#   CC_OTEL_DASHBOARD_RUN_CMD        replace the docker run invocation (tests / failure injection)
#   CC_OTEL_DASHBOARD_INSPECT_STATE  override container inspect: running|stopped|absent|aspire-dashboard-running|docker-absent

set -euo pipefail

readonly ASPIRE_DASHBOARD_CONTAINER_NAME="aspire-dashboard"
readonly DEFAULT_DASHBOARD_IMAGE="mcr.microsoft.com/dotnet/aspire-dashboard:13.4.2"
# The dashboard image always listens on 18888 (UI) / 18889 (OTLP gRPC) INSIDE the
# container; roles differ only in the published host ports and container identity.
readonly CONTAINER_UI_PORT=18888
readonly CONTAINER_OTLP_PORT=18889
readonly LABEL_COMPONENT="aspire-dashboard"
readonly LABEL_MANAGED_BY="manual"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=net-probe.sh
source "$SCRIPT_DIR/net-probe.sh"

usage() {
  cat <<'EOF'
Usage: start-dashboard.sh [--role cc|apps] [--dry-run] [--help]

Idempotent ensure-running for a local OTEL Aspire dashboard (optional live tail).
Roles: cc (default) = Claude Code telemetry, UI :18888 / OTLP :18889;
       apps = app/default-route telemetry, UI :19888 / OTLP :19889.
Spawns the pinned aspire-dashboard image with purpose-based naming and identification
labels only when the role's container is absent and its ports are free. Advisory: skip
paths exit 0.

Options:
  --role cc|apps   Which dashboard to ensure (default: cc).
  --dry-run        Report container name, image, ports, labels, and action; never spawn.
  --help           Show this help.

Env:
  CC_OTEL_DASHBOARD_IMAGE          dashboard image ref
  CC_OTEL_DASHBOARD_RUN_CMD        replace docker run (tests)
  CC_OTEL_DASHBOARD_INSPECT_STATE  override inspect (tests)
EOF
}

# Always returns 0 — prints running|stopped|absent|aspire-dashboard-running|docker-absent.
container_state() {
  local container_name="$1"
  if [[ -n "${CC_OTEL_DASHBOARD_INSPECT_STATE:-}" ]]; then
    printf '%s\n' "${CC_OTEL_DASHBOARD_INSPECT_STATE}"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' "docker-absent"
    return 0
  fi
  if docker inspect "$container_name" >/dev/null 2>&1; then
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || echo false)" == "true" ]]; then
      printf '%s\n' "running"
      return 0
    fi
    printf '%s\n' "stopped"
    return 0
  fi
  if docker inspect "$ASPIRE_DASHBOARD_CONTAINER_NAME" >/dev/null 2>&1; then
    if [[ "$(docker inspect -f '{{.State.Running}}' "$ASPIRE_DASHBOARD_CONTAINER_NAME" 2>/dev/null || echo false)" == "true" ]]; then
      printf '%s\n' "aspire-dashboard-running"
      return 0
    fi
  fi
  printf '%s\n' "absent"
}

run_dashboard_create() {
  local image="$1" container_name="$2" host_ui_port="$3" host_otlp_port="$4"
  local label_role="$5" label_stack="$6" label_oci_title="$7"
  if [[ -n "${CC_OTEL_DASHBOARD_RUN_CMD:-}" ]]; then
    # shellcheck disable=SC2090
    "$CC_OTEL_DASHBOARD_RUN_CMD"
    return 0
  fi
  docker run -d --rm \
    --name "$container_name" \
    -p "${host_ui_port}:${CONTAINER_UI_PORT}" \
    -p "${host_otlp_port}:${CONTAINER_OTLP_PORT}" \
    -e ASPIRE_DASHBOARD_UNSECURED_ALLOW_ANONYMOUS=true \
    --label "local.dev.container.component=${LABEL_COMPONENT}" \
    --label "local.dev.container.role=${label_role}" \
    --label "local.dev.container.stack=${label_stack}" \
    --label "local.dev.container.managed-by=${LABEL_MANAGED_BY}" \
    --label "org.opencontainers.image.title=${label_oci_title}" \
    "$image"
}

main() {
  local dry_run=false role="cc"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role)
        shift
        role="${1:-}"
        ;;
      --dry-run) dry_run=true ;;
      --help | -h)
        usage
        return 0
        ;;
      *)
        printf 'start-dashboard.sh: unknown argument %q\n\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
    shift
  done

  local container_name host_ui_port host_otlp_port label_role label_stack label_oci_title
  case "$role" in
    cc)
      container_name="local-otel-dashboard-claude-code"
      host_ui_port=18888
      host_otlp_port=18889
      label_role="otel-live-tail"
      label_stack="claude-code-observability"
      label_oci_title="Local OTEL live-tail dashboard (Claude Code observability)"
      ;;
    apps)
      container_name="local-otel-dashboard-apps"
      host_ui_port=19888
      host_otlp_port=19889
      label_role="app-otel-live-tail"
      label_stack="local-app-observability"
      label_oci_title="Local OTEL live-tail dashboard (app telemetry, collector default route)"
      ;;
    *)
      printf 'start-dashboard.sh: unknown role %q (expected cc or apps)\n\n' "$role" >&2
      usage >&2
      return 2
      ;;
  esac

  local image state ui_port_state otlp_port_state action
  image="${CC_OTEL_DASHBOARD_IMAGE:-$DEFAULT_DASHBOARD_IMAGE}"
  state="$(container_state "$container_name")"
  ui_port_state="$(port_status "$host_ui_port")"
  otlp_port_state="$(port_status "$host_otlp_port")"

  case "$state" in
    running) action="noop-already-running" ;;
    stopped) action="would-start" ;;
    aspire-dashboard-running) action="skip-aspire-dashboard-present" ;;
    docker-absent) action="skip-docker-absent" ;;
    absent)
      # docker run publishes BOTH ports; either one being bound dooms the bind.
      if [[ "$ui_port_state" == "listening" || "$otlp_port_state" == "listening" ]]; then
        action="skip-port-in-use"
      else
        action="would-spawn"
      fi
      ;;
    *)
      action="skip-unknown-state"
      ;;
  esac

  printf 'role=%s\n' "$role"
  printf 'container_name=%s\n' "$container_name"
  printf 'image=%s\n' "$image"
  printf 'ports=%s,%s\n' "$host_ui_port" "$host_otlp_port"
  printf 'port_%s=%s\n' "$host_ui_port" "$ui_port_state"
  printf 'port_%s=%s\n' "$host_otlp_port" "$otlp_port_state"
  printf 'label_stack=%s\n' "$label_stack"
  printf 'label_component=%s\n' "$LABEL_COMPONENT"
  printf 'label_role=%s\n' "$label_role"
  printf 'label_managed_by=%s\n' "$LABEL_MANAGED_BY"
  printf 'label_oci_title=%s\n' "$label_oci_title"
  printf 'container_state=%s\n' "$state"
  printf 'action=%s\n' "$action"

  if [[ "$dry_run" == true ]]; then
    return 0
  fi

  case "$action" in
    noop-already-running)
      return 0
      ;;
    skip-aspire-dashboard-present)
      printf 'start-dashboard.sh: container %q is still running — stop/remove it, then re-run:\n' "$ASPIRE_DASHBOARD_CONTAINER_NAME" >&2
      printf '  docker stop %s && docker rm %s\n' "$ASPIRE_DASHBOARD_CONTAINER_NAME" "$ASPIRE_DASHBOARD_CONTAINER_NAME" >&2
      printf '  bash start-dashboard.sh --role %s\n' "$role" >&2
      return 0
      ;;
    skip-port-in-use)
      printf 'start-dashboard.sh: port %s is in use but %s is not running — resolve the conflict manually.\n' "$host_ui_port" "$container_name" >&2
      return 0
      ;;
    skip-docker-absent)
      printf 'start-dashboard.sh: docker not on PATH — dashboard live tail unavailable (advisory).\n' >&2
      return 0
      ;;
    would-start)
      docker start "$container_name" >/dev/null
      printf 'start-dashboard.sh: started existing container %s\n' "$container_name" >&2
      return 0
      ;;
    would-spawn)
      run_dashboard_create "$image" "$container_name" "$host_ui_port" "$host_otlp_port" \
        "$label_role" "$label_stack" "$label_oci_title" >/dev/null
      printf 'start-dashboard.sh: spawned dashboard container %s\n' "$container_name" >&2
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

main "$@"
