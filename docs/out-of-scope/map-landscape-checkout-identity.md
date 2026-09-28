# map-landscape checkout identity

Triage park for
[#4554](https://github.com/melodic-software/claude-code-plugins/issues/4554).
This is a leftover of #4559 in the existing `map-landscape` skill, not a
member of the unpaid map-* family in
[`map-skills-below-landscape.md`](map-skills-below-landscape.md).

## Decision

**Park. Do not change record keys.** `portfolio-facts.sh` and
`reference-edges.sh` keep `name="$(basename "$repo")"`. Origin-based identity
waits until a maintainer accepts the one-time `landscape.json` key drift.

**Claim:** map-landscape identifies a checkout by its directory name until a
maintainer funds origin-based identity and accepts the one-time drift that
change causes in committed records.
**Basis:** #4554 (`needs-triage`). `portfolio-facts.sh` and `reference-edges.sh`
both set `name` from `basename` of the checkout path. The proposed fix
(origin owner/repo when resolvable, directory name otherwise) changes record
keys for any consumer whose committed `landscape.json` was generated from a
differently named checkout. The phantom self-edge half already shipped in
#4559. This is not a new map-* skill.
**As of:** 2026-09-28.
**Recheck:** a maintainer accepts the one-time landscape.json key drift and
unparks #4554.

## Rationale

- The bug is real on worktrees and differently named clones.
- The fix is a record-key migration, not a silent rename. Drift comparison
  would report one repository removed and another added unless consumers
  regenerate.
- `needs-triage` with no work-class. Not declined as unpaid map-* family.

## Revisit when

- A maintainer accepts the one-time drift and funds the origin-based key, or
- A follow-up records a migration that rewrites committed keys in place.

## Prior requests

- #4554 (2026-09-28): leftover of #4559; Option A park of the identity change.
