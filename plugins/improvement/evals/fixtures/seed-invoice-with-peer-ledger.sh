#!/usr/bin/env bash
set -euo pipefail

fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace="$PWD"

bash "$fixtures/seed-invoice-service.sh"
printf 'peer/\n' >>.git/info/exclude

mkdir -p peer/seed
(cd peer/seed && bash "$fixtures/seed-ledger-cli.sh")
git clone -q --bare peer/seed peer/ledger-cli.git
git clone -q peer/ledger-cli.git peer/ledger-cli
rm -rf "${workspace:?}/peer/seed"
