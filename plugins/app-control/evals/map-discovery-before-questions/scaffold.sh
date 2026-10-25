#!/usr/bin/env bash
# Seeds a small shop app whose README answers the Run and Ready discovery rows.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -R "$here/fixtures/shop/." .
