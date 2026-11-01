#!/usr/bin/env bash
# Seed release tagging rules written out in two files with drifted wording and no declared owner.
set -euo pipefail

mkdir -p docs .github
cat >CONTRIBUTING.md <<'MD'
# Contributing

## Pull requests

Open a pull request against `main`. One approving review is required before merge.

## Release tags

Tag releases as `vMAJOR.MINOR.PATCH`, from `main` only, after the release workflow passes. Never
move or delete a tag once it is pushed; ship a new patch version instead. Hotfix tags add the
suffix `-hotfix.N`, counting from 1.
MD
cat >docs/releasing.md <<'MD'
# Releasing

## Changelog

Move the entries under "Unreleased" into a new dated section before you tag.

## Tagging

Release tags take the form `vX.Y.Z` and are cut from the `main` branch once the release workflow
is green. A pushed tag is permanent: do not retag or delete it; publish the next patch instead.
For a hotfix, append `-hotfix.N` to the tag, starting at 1.

## Announcing

Post the changelog section in the #releases channel.
MD
cat >README.md <<'MD'
# Lumen

Lumen renders status pages from a YAML file. The current release is v2.3.0.

See CONTRIBUTING.md for how to propose changes and how releases are tagged.
MD
cat >.github/pull_request_template.md <<'MD'
## What changed

## Checklist

- [ ] Tests pass locally
- [ ] If this is a release, I tagged it as CONTRIBUTING.md describes
MD
