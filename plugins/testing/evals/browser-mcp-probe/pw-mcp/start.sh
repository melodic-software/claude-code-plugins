#!/usr/bin/env bash
# Starts @playwright/mcp 0.0.83, the version the root package.json locks, on the
# Chromium that .github/workflows/eval-browser-dispatch.yml installs under
# /opt/pw. The eval's env allowlist drops PLAYWRIGHT_BROWSERS_PATH, so the
# browser is pinned by path, as browser-probe/scaffold.sh does. File access is
# unrestricted, like browser-probe's configs, so the canary step measures the
# eval's isolation and not the server's own file:// policy.
set -euo pipefail
shopt -s nullglob

version=$(playwright-mcp --version)
if [[ "$version" != "Version 0.0.83" ]]; then
  echo "start.sh: expected @playwright/mcp 0.0.83 on PATH, found: $version" >&2
  exit 1
fi

# A missing install leaves a path that fails loudly at the first navigate.
chrome=/opt/pw/chromium-not-found
for candidate in /opt/pw/chromium-*/chrome-linux*/chrome; do
  chrome="$candidate"
done

exec playwright-mcp --headless --isolated --allow-unrestricted-file-access --executable-path "$chrome"
