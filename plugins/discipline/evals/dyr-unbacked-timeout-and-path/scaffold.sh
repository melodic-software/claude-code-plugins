#!/usr/bin/env bash
# Seed a small HTTP client whose source holds the real timeout default and config path.
set -euo pipefail

here="$(pwd -P)"
run_home="$(cd "${HOME:?}" && pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${run_home}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -n "${real_home}" && "${run_home}" == "$(cd "${real_home}" 2>/dev/null && pwd -P)" ]]; then
  echo "refusing to scaffold: HOME is the real home" >&2 && exit 3
fi
case "${here}/" in
"${run_home}"/*) ;;
*) echo "refusing to scaffold outside HOME: ${here}" >&2 && exit 3 ;;
esac
for target in client conf; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2 && exit 3
  fi
done

mkdir -p client conf
cat >client/settings.py <<'PY'
DEFAULT_CONNECT_TIMEOUT = 10  # seconds to open a connection
READ_TIMEOUT = 30  # seconds to wait for a response once connected
RETRIES = 2
PY
cat >client/config.py <<'PY'
from pathlib import Path

CONFIG_PATH = Path("conf/client.toml")


def load():
    return CONFIG_PATH.read_text()
PY
cat >conf/client.toml <<'TOML'
base_url = "https://api.example.internal"
TOML
