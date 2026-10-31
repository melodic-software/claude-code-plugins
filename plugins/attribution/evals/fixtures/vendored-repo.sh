#!/usr/bin/env bash
# A small repository whose tracked markdown includes a vendor/ tree and a third_party/ tree marked
# linguist-vendored, the two built-in carve-outs of the corpus listing. Every file is tracked.
set -euo pipefail
git init -q -b main .
mkdir -p docs vendor/widget-sdk third_party/gizmo
cat >docs/guide.md <<'MD'
# Contributor guide

Open a branch per change, keep each pull request to one concern, and run the test suite before
asking for review. We squash on merge.
MD
cat >vendor/widget-sdk/README.md <<'MD'
# Widget SDK

The Widget SDK wraps the Widget Runner API. Install it with `widget install sdk` and call
`connect()` before any other method.
MD
cat >third_party/gizmo/NOTES.md <<'MD'
# Gizmo notes

Gizmo reads its settings from `gizmo.toml` in the working directory and falls back to defaults.
MD
printf '%s\n' 'third_party/** linguist-vendored' >.gitattributes
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
