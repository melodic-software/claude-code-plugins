# Deviations log — overengineering-detection-skill implementation

Conservative deviations taken during autonomous orchestrated implementation, per the
implement-dispatch non-interactive divergence rule. Reviewed at PR time.

## Phase 1 (commit b8e7464a)

1. **Layer enum made forge-neutral.** `design/design-resolution.md`'s type sketch listed
   `github-apps`; the shipped `context/findings-artifact.md` enum uses `forge-apps` (whole enum:
   `agent-hooks · agent-instructions · repo-hooks · vcs-hooks · ci-lanes · gate-scripts ·
   satellite-workflows · branch-protection · forge-apps · external-integrations`). A baked forge
   name violates the Brief's consumer-agnostic constraint and is the token class the portability
   gate polices. Blast radius: Phases 3–4 must use this enum, not the sketch's.
2. **Refuted "no consumer means retire" claim appears once, explicitly marked refuted.** The plan
   said the claim "must NOT appear"; the shipped `scrutiny-method.md` §9 closes with a paragraph
   recording it as refuted and deliberately not a rule, so later readers do not re-derive it as an
   obvious inference. Read as truer to the plan's intent (the claim must not be *cited as
   support*); deletes cleanly if the reviewer disagrees (last paragraph of §9).
3. **Finding-id constituents specified concretely** (`check`/`claim`/`sites` shapes with
   `anchor/v1`), beyond the plan's "per the finding-suppression id discipline" — required for the
   durable judgment record to be implementable; the hash computation itself is pointed at, not
   restated.
4. **Forward pointers to Phase 2 files** (`reference/consumer-config.md`, `reference/topic-docs.md`)
   ship one phase before those files exist. Resolves when Phase 2 lands (same PR).

Known transient: `scripts/check-plugin-manifest-presence.sh` is red between Phase 1 and Phase 2
(plugin directory exists, marketplace entry not yet added — Phase 2 owns it).
