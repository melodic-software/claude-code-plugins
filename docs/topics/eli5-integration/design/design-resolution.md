# Design resolution — eli5-integration

outcome: early-exit (Tier B, light design)

Reason: the design surface is instruction markdown, not code types. The one new
"contract" is the eli5 skill's behavioral shape, and it was designed and
resolved through the interview's 4 rounds plus the validation pipeline
(dual-verified explore/research, blindspot, brainstorm with a Design-It-Twice-
style coupling-axis spread, fresh-context devils-advocate and scrutiny, and a
two-validator answer audit), locked in the Brief with the owner's final
sign-off on all 18 decisions (2026-09-01).

Type sketch (the skill contract, from the Brief):

- education:eli5 — auto-invoking wrapper skill. Inputs: free-text topic
  (argument-hint), or conversational ELI5 asks. Behavior rungs:
  1. grounding pre-pass keyed on object type (module/tradeoff/incident/general)
  2. presence-gate: upstream eli5@claude-community installed -> Skill-tool
     delegate; absent or invocation fails -> original-prose inline fallback;
     absent -> print-only install-assist first
  3. output contract: "a visual HTML explainer that assumes zero prior
     knowledge: one idea per diagram, minimal text"
- education:explain — unchanged mechanism; six ELI5-branding sites removed;
  gains one boundary line + cross-offer.
- adhd:clarify — boundary becomes a three-way split (structure / prose
  altitude drop -> explain / picture explainer -> eli5).

Design-defaults audit (per /planning:plan Step 2): configurability — none
added (no userConfig; deliberate, sign-off Q8 alternatives rejected);
extension points — upstream-drift stamp + recheck trigger is the sole seam;
observability — n/a (no runtime code); testability — evals are the test
surface (birth evals enumerated in the Brief's acceptance criteria).
