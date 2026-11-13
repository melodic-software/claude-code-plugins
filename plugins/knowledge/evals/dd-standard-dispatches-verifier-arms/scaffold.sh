#!/usr/bin/env bash
# A docpage-digest slice with Phases 1 to 3 ticked, in a repository whose default branch sets
# verification: standard for the knowledge plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf 'verification: standard\n' >docs/conventions/knowledge.yaml
printf '.work/\n' >.gitignore
printf '# demo\n' >README.md
git add -A
git commit -q -m "chore: demo"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git remote set-head origin main

root=.work/docs-example-com-api-overview-138253a9
mkdir -p "$root/digests" "$root/verification"
printf '*\n' >.work/.gitignore
cat >"$root/source.md" <<'MD'
# API overview

The API serves JSON over HTTPS.

## Rate limits

Each key may send 100 requests per minute.
MD
cat >"$root/SOURCES.md" <<'MD'
---
abstract: The API overview page, covering transport and rate limits.
---

# Sources

## Headings

| line | level | text |
|---|---|---|
| 1 | 1 | API overview |
| 5 | 2 | Rate limits |

## Digest map

| digest file | START-END |
|---|---|
| digests/00-introduction.md | 1-4 |
| digests/01-rate-limits.md | 5-7 |

## Status

- [x] digests/00-introduction.md
- [x] digests/01-rate-limits.md
MD
for unit in 00-introduction 01-rate-limits; do
  case "$unit" in
    00-introduction) quote='The API serves JSON over HTTPS.' ;;
    *) quote='Each key may send 100 requests per minute.' ;;
  esac
  cat >"$root/digests/$unit.md" <<MD
# $unit

## Summary

The section's one claim, quoted below.

## Key claims (verbatim)

**C1.**

\`\`\`text
$quote
\`\`\`

## Prompt snippets (exact)

None.

## Implications for daily use

None beyond the claim.

## Candidate artifacts

None.

## Open questions for interview

None.
MD
done
cat >"$root/docpage-digest-checklist.md" <<'MD'
# /knowledge:docpage-digest Checklist

## Provenance

- Canonical URL: https://docs.example.com/api/overview
- Fetch date: 2026-11-01
- Fetch channel (raw-md / rendered / binary+extraction): raw-md
- Extraction tooling: n/a
- Publisher profile used (or "no profile"): no profile
- Resolved work root: .work/docs-example-com-api-overview-138253a9

## Phases

- [x] Phase 1: Fetch
- [x] Phase 2: Inventory
- [x] Phase 3: Digest fan-out (every digest agent returned)
- [ ] Phase 4: Dual verification
  - Verifier A effort:
  - Verifier B effort:
  - Verification status: unverified: not recorded
- [ ] Phase 5: Interview handoff
MD
