#!/usr/bin/env bash
# Seeds a shop app that sends real mail and signs in through a shared identity server.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -R "$here/fixtures/shop/." .
