#!/usr/bin/env bash
# Regression sweep for the youtube-digest -> video-digest skill rename: fail on
# any resurfacing "youtube-digest" reference so a stale ref (vendored doc, new
# consumer, revert artifact) breaks CI loudly instead of failing silently at a
# consumer surface.
#
#   scripts/check-rename-sweep.sh
#
# Scans tracked AND untracked (non-ignored) files, excluding immutable
# historical/session records (docs/topics/, .work/ — retained by decision, see
# the source-agnostic-video-digest plan's Decisions table).
#
# Explicit inline allowlist — the only places the old name may live:
#   1. plugins/knowledge/CHANGELOG.md — historical entries are immutable, and
#      the 0.13.0 breaking entry must name the old name to document the rename.
#   2. plugins/knowledge/skills/video-digest/SKILL.md lines carrying the quoted
#      '/youtube-digest' trigger phrase — the migration alias the Phase 6
#      trigger-token baseline requires verbatim.
#   3. This script and its self-test — the sweep must name the token it hunts.
#   4. Fixture-test negative assertions (.not.toContain("youtube-digest")) in
#      the video-digest extraction suite — the regression guards that pin the
#      renamed resume prompt and recovery command.
#   5. The two ADRs documenting the rename decisions (0012 adapter registry,
#      0013 storage-format stability) — same historical-record class as the
#      CHANGELOG: an ADR recording the rename must name the old name.
#
# Exit 0 when only allowlisted hits remain; exit 1 listing every violation.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

hits="$(git grep -nI --untracked -e "youtube-digest" -- ':!.git' ':!docs/topics' ':!.work' 2>/dev/null)"

violations="$(printf '%s\n' "$hits" | grep -v \
  -e '^plugins/knowledge/CHANGELOG\.md:' \
  -e "^plugins/knowledge/skills/video-digest/SKILL\.md:[0-9]*:.*'/youtube-digest'" \
  -e '^scripts/check-rename-sweep\.\(sh\|test\.sh\):' \
  -e '^plugins/knowledge/skills/video-digest/extraction/.*\.test\.js:[0-9]*:.*\.not\.toContain("youtube-digest")' \
  -e '^docs/adr/0012-dispatch-video-sources-through-a-static-adapter-registry\.md:' \
  -e '^docs/adr/0013-keep-storage-format-identifiers-stable-across-renames\.md:' \
  | grep -v '^$')" || true

if [ -n "$violations" ]; then
  printf 'FAIL: stale youtube-digest reference(s) outside the allowlist:\n%s\n' "$violations" >&2
  exit 1
fi

echo "OK: no youtube-digest references outside the allowlist."
