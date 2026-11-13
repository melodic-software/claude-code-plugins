#!/usr/bin/env bash
# Checks bwrap and socat are on PATH, then starts a bwrap sandbox bare and
# with playwright-cli, as the Bash sandbox of an eval run does.
set -e
fail() {
  local msg=${2//'%'/'%25'}
  msg=${msg//$'\r'/'%0D'}
  echo "::error::$1: ${msg//$'\n'/'%0A'}"
  exit 1
}
for tool in bwrap socat; do
  command -v "$tool" || fail "$tool is not on PATH" "the Bash sandbox needs it"
done
sysctl kernel.apparmor_restrict_unprivileged_userns || true
sandbox=(bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --unshare-all --die-with-parent)
if ! out=$("${sandbox[@]}" true 2>&1); then
  fail "bwrap cannot start a sandbox as the runner user" "$out"
fi
if ! out=$("${sandbox[@]}" playwright-cli --version 2>&1); then
  fail "playwright-cli does not start inside bwrap" "$out"
fi
echo "playwright-cli inside bwrap: $out"
