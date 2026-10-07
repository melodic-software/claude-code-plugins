#!/usr/bin/env bash
# A skill directory before and after a rewrite: the retention paragraph moved from SKILL.md into
# reference/retention.md, the 50 MB rotation threshold was dropped, and cuts.md lists the one
# intended cut (the tidy-logs filler line).
set -euo pipefail

mkdir -p before after/reference

cat > before/SKILL.md <<'MD'
# Rotate logs

This skill helps you keep your logs tidy.

Run `scripts/rotate.sh` from the repository root.

Rotate a log file only when it exceeds 50 MB; smaller files stay in place.

## Retention

Keep the last 7 rotated archives and delete older ones. Archives are gzip-compressed and named
`<service>-<date>.log.gz`, so `ls -t` lists the newest first.
MD

cat > after/SKILL.md <<'MD'
# Rotate logs

Run `scripts/rotate.sh` from the repository root.

Rotate a log file only when it is large; smaller files stay in place.

Retention: [reference/retention.md](reference/retention.md).
MD

cat > after/reference/retention.md <<'MD'
# Retention

Keep the last 7 rotated archives and delete older ones. Archives are gzip-compressed and named
`<service>-<date>.log.gz`, so `ls -t` lists the newest first.
MD

cat > cuts.md <<'MD'
- "This skill helps you keep your logs tidy." Deletion test: no reader acts differently without it.
MD
