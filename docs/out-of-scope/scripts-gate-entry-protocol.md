# Scripts gate-entry protocol hoist

Recorded park for
[#3413](https://github.com/melodic-software/claude-code-plugins/issues/3413),
a deepening candidate that would hoist mode dispatch, parent-shell base-ref
validation, target discovery, and the fail-closed 0/1/2 mapping into one
`scripts/lib/` module.

## Decision

**Park. Do not hoist.** Per-gate entry stays. `changed_files::verify_base` stays
the only shared parent-shell base-ref check.

- **Option A (taken):** no unpaid hoist. Gates keep their own mode dispatch,
  target discovery, and exit-code mapping. Remaining hand-rolled
  `git rev-parse --verify --quiet "...^{commit}"` predicates are per-gate
  cleanup, not a reason to design a new module from this record.
- **Option B (declined):** one gate-entry module that owns mode dispatch,
  parent-shell base-ref validation, target discovery, and 0/1/2 mapping, with
  every gate migrated onto it.

**Claim:** CI gates under `scripts/` keep their own entry protocol. The only
shared parent-shell base-ref helper is `changed_files::verify_base` in
`scripts/lib/changed-files.sh`. A single gate-entry module is unpaid.
**Basis:** origin/main as of this record. `scripts/lib/` has no gate-entry
module. `changed_files::verify_base` is called by `affected-tests.sh`,
`check-changed-skills.sh`, `check-changelog-parity.sh`,
`check-contract-slice-prune.sh`, `check-docs-only.sh`,
`check-shell-portability.sh`, `check-skill-portability.sh`,
`check-skill-precompute-compose.sh`, `check-stale-base-overlap.sh`, and
`check-vendor-version-bump.sh`. Hand-rolled `^{commit}` predicates remain in
`ai-slop-report.sh`, `check-guardrails-ps-differential.sh`,
`check-silent-revert.sh`, and the HEAD check in `check-stale-base-overlap.sh`.
#3377 / #3395 (ce499a586) is the worked failure: a hand-rolled check inside
`mapfile < <(...)` let `exit 2` kill only the subshell. The 0/1/2 contract is
still restated as prose per gate. `docs/conventions/shell-test-helpers/README.md`
permits shared code at the repo-tooling layer; it does not require this hoist.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds `scripts/lib/gate-entry.sh` (or equivalent) with
a suite that asserts an unresolvable base ref exits 2 in the parent shell,
`--all` and `--paths` never consult a ref, and an empty discovered set is
distinguishable from a failed discovery; or every remaining hand-rolled
`^{commit}` predicate is deleted without that module.

## Rationale

- Adoption of `verify_base` already closed the #3377 class for the gates that
  call it. The leftover hand-rolls are a grep-checkable cleanup, not proof that
  mode dispatch and 0/1/2 mapping must move with them.
- Mode triads still differ per gate (`<base-ref> | --all | --paths` is not
  universal). A module that forced one triad would rewrite gates that never
  offered those modes.
- The issue is `work-class: structural` and `needs-human`. An autonomous hoist
  across the gate fleet is the unpaid work this park refuses.

## Revisit when

- A maintainer funds the module and names the first gates to migrate, or
- a new gate reproduces the #3377 swallowed-exit class after adopting
  `verify_base`.

## Prior requests

- #3413 (2026-09-28): deepening candidate; Option A recorded here.
