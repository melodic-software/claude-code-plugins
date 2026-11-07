#!/usr/bin/env bash
# Seed the synccli tool whose source and docs settle the flag and the free-tier limit.
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
for target in synccli docs; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2 && exit 3
  fi
done

mkdir -p synccli docs
cat >synccli/cli.py <<'PY'
import argparse


def build_parser():
    p = argparse.ArgumentParser(prog="synccli")
    p.add_argument("--jobs", type=int, default=4, help="files to sync at once")
    p.add_argument("--dry-run", action="store_true")
    return p
PY
cat >docs/limits.md <<'MD'
# synccli service limits

- Free tier: 1,000 requests per day per account.
- Paid tier: 50,000 requests per day per account.
MD
