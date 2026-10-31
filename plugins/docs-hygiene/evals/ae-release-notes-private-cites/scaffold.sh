#!/usr/bin/env bash
# Seed a repo whose release doc cites a skill's private reference file and heading anchor beside legal slash, SKILL.md and scripts/ cites.
set -euo pipefail

mkdir -p .claude/skills/release-notes/reference .claude/skills/release-notes/scripts docs .github/workflows

cat >.claude/skills/release-notes/SKILL.md <<'MD'
---
name: release-notes
description: Draft release notes from merged pull requests since the last tag. Use when preparing a release.
---

# Release notes

## Actions

- `draft <version>`: collect merged pull requests since the last tag with
  `scripts/collect-prs.sh` and write the notes in the layout in
  [reference/changelog-format.md](reference/changelog-format.md).

## Version bump rules

- A pull request labeled `breaking` bumps the major version.
- A pull request labeled `feature` bumps the minor version.
- Everything else bumps the patch version.
MD

cat >.claude/skills/release-notes/reference/changelog-format.md <<'MD'
# Changelog format

Group entries under `### Added`, `### Changed` and `### Fixed`, in that order. One line per pull
request: the title in sentence case, then the number in parentheses.
MD

cat >.claude/skills/release-notes/scripts/collect-prs.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
git log --merges --format='%s' "$(git describe --tags --abbrev=0)..HEAD"
SH
chmod +x .claude/skills/release-notes/scripts/collect-prs.sh

cat >docs/releasing.md <<'MD'
# Releasing

1. Run `/release-notes draft <version>` on the release branch.
2. Check that every entry follows the layout in
   `.claude/skills/release-notes/reference/changelog-format.md` before you paste it into the
   release pull request.
3. Choose the version number with the rules in
   `.claude/skills/release-notes/SKILL.md#version-bump-rules`.
4. Tag the merge commit and push the tag.
MD

cat >docs/tooling.md <<'MD'
# Tooling

The release-notes skill drafts release notes; its entry point is
`.claude/skills/release-notes/SKILL.md`. Invoke it as `/release-notes`.
MD

cat >.github/workflows/release.yml <<'YML'
name: release
on:
  push:
    tags: ["v*"]
jobs:
  notes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: bash .claude/skills/release-notes/scripts/collect-prs.sh
YML

cat >README.md <<'MD'
# Tidewater

Inventory service. Release steps are in `docs/releasing.md`.
MD
