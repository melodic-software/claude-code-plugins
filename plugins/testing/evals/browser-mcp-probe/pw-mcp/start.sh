#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

locked=$(node -p 'require("/opt/tools/package.json").devDependencies["@playwright/mcp"]')
version=$(playwright-mcp --version)
if [[ "$version" != "Version $locked" ]]; then
  echo "start.sh: expected @playwright/mcp $locked (/opt/tools/package.json) on PATH, found: $version" >&2
  exit 1
fi

chrome=/opt/pw/chromium-not-found
for candidate in /opt/pw/chromium-*/chrome-linux*/chrome; do
  chrome="$candidate"
done

exec playwright-mcp --headless --isolated --allow-unrestricted-file-access --executable-path "$chrome"
