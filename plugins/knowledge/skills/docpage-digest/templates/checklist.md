# /knowledge:docpage-digest Checklist

Copy into `<work-root>/docpage-digest-checklist.md`. Tick each phase as it completes; the ticked
state is the cross-session resume pointer.

## Provenance

- Canonical URL:
- Fetch date:
- Fetch channel (raw-md / rendered / binary+extraction):
- Publisher profile used (or "no profile"):

## Phases

- [ ] Phase 1: Fetch — unaltered original snapshotted to `source.md` (immutable)
- [ ] Phase 2: Inventory — `INDEX.md` written (headings, themes, digest map, status rows)
- [ ] Phase 3: Digest fan-out — one agent per digest unit → `digests/NN-slug.md` (fixed structure)
- [ ] Phase 4: Dual verification — Verifier A (same-vendor) + Verifier B (cross-vendor) verdicts
      in `verification/` (append-only; degraded fallback recorded, never silent)
- [ ] Phase 5: Interview handoff — `interview-handoff.md` authored; `/planning:interview` run or
      artifact presented

## Skip criteria

- Phase 4 Verifier B — degrade per SKILL.md only when the cross-vendor verifier is genuinely
  unavailable; record reason in the verdict header
- Phase 5 interview invocation — skip (present artifact only) when the planning plugin is absent
