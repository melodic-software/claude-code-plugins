# Design resolution — boris-video-absorption

outcome: early-exit (Tier B)

No new types, modules, or package topology. One new consumer-config
surface resolved here:

- Surface: `.claude/testing/e2e.md` (folder-form name; identity = whole
  path relative to `.claude/`, per
  `docs/conventions/config-cascade/README.md`).
- Keys (owned by the testing plugin's bundled reference,
  `run-e2e/context/e2e-config.md`): `recording: video | gif | off`
  (default `off`), `browser_mode: headed | headless` (default
  `headless`).
- Merge: per-key override across the convention's three layers
  (user-global → team → local overlay).
- Rationale: knobs are per-operator/per-repo visibility and evidence
  preferences — exactly the axis the layering convention exists for;
  defaults preserve current behavior (screenshots-floor evidence,
  headless driving).

Everything else is prose amendment to existing skill/contract documents
— no design threads.
