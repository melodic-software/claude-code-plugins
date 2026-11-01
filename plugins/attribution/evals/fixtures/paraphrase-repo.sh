#!/usr/bin/env bash
# One tracked doc that restates a fictional vendor's retry defaults in its own words, with a link
# to a page that cannot be fetched (example.invalid), so no span can be fingerprint-confirmed.
set -euo pipefail
git init -q -b main .
mkdir -p docs
cat >docs/retry-defaults.md <<'MD'
# Retry defaults

Widget Runner gives a failed step three more tries before it gives up, waiting thirty seconds
between tries, and it will not go above ten tries however the key is set. See the vendor's
retry page at https://docs.example.invalid/widget-runner/retry for the details.

We keep the defaults for every pipeline except the nightly import, which sets five tries.
MD
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
