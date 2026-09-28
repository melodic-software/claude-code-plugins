# Handoff verified is not CI-green (#3953)

Option A: document the caveat and fix the wording. Option B (a pending-verification
field in the handoff shape) is parked.

## Decision record

- **Claim:** A save-point may call a status claim verified only for what this session
  observed. A pushed commit, a "CI is running" observation, or a local test pass is not
  CI-green. A fix still in CI, merge, or another unreturned check is
  `UNVERIFIED (<check>)`, naming the run id, job name, or PR check. A dedicated
  pending-verification field in the handoff shape is unpaid and parked.
- **Basis:** Issue [#3953](https://github.com/melodic-software/claude-code-plugins/issues/3953).
  Engine doc `reference/save-point.md` "Claim provenance" already required an
  `UNVERIFIED (<source>)` marker for inherited claims; it did not say that a pushed SHA
  is not CI-green. The meta-muse phase-7 handoff recorded `8ffb18f` as the CI fix while
  CI was still red; `9dddfcd` landed about twenty minutes later and the handoff was never
  amended.
- **As of:** 2026-09-28.
- **Recheck:** a maintainer funds a pending-verification field in `structure.md`, or
  "Claim provenance" again lets a pending CI check read as plain fact.

## Options

| Option | Scope | When to choose |
| --- | --- | --- |
| **A: Wording plus caveat (taken)** | Claim provenance names pending CI as unverified; checklist ticks it | Docs-only; what this settle ships |
| **B: Shape field (parked)** | A machine-visible pending-verification field on the handoff | Structural; unpaid |

## Park

Do not add a pending-verification field to the save-point shape in this settle. Track that
rebuild under #3953 until funded.
