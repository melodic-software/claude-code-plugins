#!/usr/bin/env bash
# Scan git history for secrets over the commits the current GitHub event owns.
#
# gitleaks/gitleaks-action src/gitleaks.js Scan() (master, read 2026-09-28,
# https://github.com/gitleaks/gitleaks-action/blob/master/src/gitleaks.js):
#   pull_request: --log-opts=--no-merges --first-parent <base>^..<head>
#   push, base == head: --log-opts=-1
#   push, otherwise: --log-opts=--no-merges --first-parent <before>^..<after>
#   any other event: no --log-opts, so gitleaks walks every commit it is given
#
# melodic-software/ci-workflows .github/actions/gitleaks scan.sh (v0.29.1)
# maps scan-mode git to --log-opts=--all. That walks every ref in the clone.
# This repository's checkout-with-base unshallows the checkout, and a full
# fetch advertises every branch, so scan-mode git is the #3599 blast radius:
# a finding on one branch fails hygiene on every other branch.
#
# pull_request and push therefore use the action's event range. workflow_dispatch
# has no range; it scans the checked-out commit (-1) rather than --all.
# A missing SHA, or the all-zero push "before" of a brand-new ref, fails closed.
# An empty range must not exit 0.
#
#   EVENT_NAME, PR_BASE_SHA, PR_HEAD_SHA, PUSH_BEFORE, PUSH_AFTER
#   GITLEAKS_CONFIG (default .gitleaks.toml)
#   GITLEAKS_BIN (skip install when set)
#   GITLEAKS_VERSION, GITLEAKS_SHA256 (install pin; defaults match ci-workflows v0.27.1)
#
#   gitleaks-scoped-scan.sh --resolve-only
#     print the --log-opts value and exit 0. No gitleaks binary, no scan.
set -euo pipefail

RESOLVE_ONLY=0
if [[ "${1:-}" == "--resolve-only" ]]; then
  RESOLVE_ONLY=1
elif [[ -n "${1:-}" ]]; then
  echo "gitleaks-scoped-scan.sh: unknown argument: $1" >&2
  exit 2
fi

EVENT_NAME="${EVENT_NAME:-}"
PR_BASE_SHA="${PR_BASE_SHA:-}"
PR_HEAD_SHA="${PR_HEAD_SHA:-}"
PUSH_BEFORE="${PUSH_BEFORE:-}"
PUSH_AFTER="${PUSH_AFTER:-}"
GITLEAKS_CONFIG="${GITLEAKS_CONFIG:-.gitleaks.toml}"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.30.1}"
GITLEAKS_SHA256="${GITLEAKS_SHA256:-551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb}"

is_sha() {
  [[ "$1" =~ ^[0-9a-fA-F]{40}$ ]]
}

is_zero_sha() {
  [[ "$1" =~ ^0{40}$ ]]
}

fail() {
  echo "gitleaks-scoped-scan: $*" >&2
  exit 2
}

# resolve_log_opts prints one --log-opts argument.
resolve_log_opts() {
  case "$EVENT_NAME" in
  pull_request)
    is_sha "$PR_BASE_SHA" || fail "pull_request base SHA is missing or not 40 hex digits"
    is_sha "$PR_HEAD_SHA" || fail "pull_request head SHA is missing or not 40 hex digits"
    is_zero_sha "$PR_BASE_SHA" && fail "pull_request base SHA is the all-zero ref"
    is_zero_sha "$PR_HEAD_SHA" && fail "pull_request head SHA is the all-zero ref"
    printf '%s\n' "--no-merges --first-parent ${PR_BASE_SHA}^..${PR_HEAD_SHA}"
    ;;
  push)
    is_sha "$PUSH_AFTER" || fail "push after SHA is missing or not 40 hex digits"
    if [[ -z "$PUSH_BEFORE" || "$PUSH_BEFORE" == "$PUSH_AFTER" ]]; then
      printf '%s\n' "-1"
      return 0
    fi
    is_sha "$PUSH_BEFORE" || fail "push before SHA is not 40 hex digits"
    if is_zero_sha "$PUSH_BEFORE"; then
      fail "push before SHA is all zeros; refusing an all-refs scan"
    fi
    printf '%s\n' "--no-merges --first-parent ${PUSH_BEFORE}^..${PUSH_AFTER}"
    ;;
  workflow_dispatch)
    printf '%s\n' "-1"
    ;;
  *)
    fail "unsupported event '${EVENT_NAME:-<empty>}'"
    ;;
  esac
}

LOG_OPTS="$(resolve_log_opts)"

if [[ "$RESOLVE_ONLY" -eq 1 ]]; then
  printf '%s\n' "$LOG_OPTS"
  exit 0
fi

if [[ ! -f "$GITLEAKS_CONFIG" ]]; then
  fail "config not found: $GITLEAKS_CONFIG"
fi

# The range has to resolve. A missing parent would make gitleaks scan nothing
# and exit 0, which is a false green.
if [[ "$LOG_OPTS" == "-1" ]]; then
  git rev-parse --verify HEAD >/dev/null 2>&1 || fail "HEAD does not resolve"
else
  range="${LOG_OPTS#* }"
  # range is "<sha>^..<sha>" after the flags. Take the revision token.
  rev="${range##* }"
  git rev-parse --verify "${rev%%..*}" >/dev/null 2>&1 || fail "range start does not resolve: $rev"
  git rev-parse --verify "${rev##*..}" >/dev/null 2>&1 || fail "range end does not resolve: $rev"
fi

install_gitleaks() {
  local dest archive url
  dest="$(mktemp -d)"
  archive="$dest/gitleaks.tar.gz"
  url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  curl -fsSL "$url" -o "$archive"
  echo "${GITLEAKS_SHA256}  ${archive}" | sha256sum -c -
  tar -xzf "$archive" -C "$dest" gitleaks
  printf '%s\n' "$dest/gitleaks"
}

if [[ -n "${GITLEAKS_BIN:-}" ]]; then
  bin="$GITLEAKS_BIN"
else
  bin="$(install_gitleaks)"
fi

set +e
"$bin" git . --log-opts="$LOG_OPTS" --config "$GITLEAKS_CONFIG" --no-banner --redact
status=$?
set -e

if ((status != 0 && status != 1)); then
  echo "gitleaks-scoped-scan: gitleaks failed before a completed scan (exit $status)" >&2
  exit "$status"
fi
exit "$status"
