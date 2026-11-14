#!/usr/bin/env bash
# Starts the @playwright/mcp version the root package.json locks, on the
# Chromium that .github/workflows/pr-run-plugin-evals.yml installs under
# /opt/pw. The eval's env allowlist drops PLAYWRIGHT_BROWSERS_PATH, so the
# browser is pinned by path, as browser-probe/scaffold.sh does. File access is
# unrestricted, like browser-probe's configs, so the canary step measures the
# eval's isolation and not the server's own file:// policy.
set -euo pipefail
shopt -s nullglob

# The pin lives only in the root package.json, which the lane copies to
# /opt/tools; refuse a playwright-mcp on PATH that is not that version.
locked=$(node -p 'require("/opt/tools/package.json").devDependencies["@playwright/mcp"]')
version=$(playwright-mcp --version)
if [[ "$version" != "Version $locked" ]]; then
  echo "start.sh: expected @playwright/mcp $locked (/opt/tools/package.json) on PATH, found: $version" >&2
  exit 1
fi

# A missing install leaves a path that fails loudly at the first navigate.
chrome=/opt/pw/chromium-not-found
for candidate in /opt/pw/chromium-*/chrome-linux*/chrome; do
  chrome="$candidate"
done

exec playwright-mcp --headless --isolated --allow-unrestricted-file-access --executable-path "$chrome"
