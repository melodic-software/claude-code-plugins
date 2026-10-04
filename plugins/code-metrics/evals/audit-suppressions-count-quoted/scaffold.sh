#!/usr/bin/env bash
# shellcheck disable=SC2016 # $FLAGS is fixture text written into publish.sh, never expanded here
set -euo pipefail
git init -q
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'FLAGS="--quiet --no-color"' \
  '# shellcheck disable=SC2086 # the flags string is split into words on purpose' \
  'rsync $FLAGS ./site/ backup:/srv/site/' \
  '# shellcheck disable=SC2034' \
  'UNUSED_MIRROR=backup2' >publish.sh
printf '%s\n' \
  'from vendored_client import fetch_rates' \
  'rates = fetch_rates()  # type: ignore[no-untyped-call]  # the vendored client ships no stubs' >rates.py
git add publish.sh rates.py
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
