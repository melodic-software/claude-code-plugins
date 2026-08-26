# authoring-steering-skill

Brief locked via `/planning:interview me` (lane 7 of the pocock-course-lanes steering extension,
[#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909); rounds 1–2 all
answered, register gate clean, **user confirmed the shared understanding 2026-08-17**). The
verified auto-read enumeration behind the scope statement lands in the skill's reference file at
implementation.

## Brief

### TLDR

Build `docs-hygiene:write-for-agents` — a model-invoked, write-side skill firing at the moment
someone authors agent-consumed markdown. Closes the writing-for-agents re-evaluation gaps 1–2
(no authoring-time home for non-skill agent docs; completion-criteria doctrine homeless) plus
the two-loads budget, with trigger reliability gated by a shipped eval suite. The lane decided;
two filed implementation issues build it.

### Goal

Every act of writing agent-consumed markdown — CLAUDE.md/AGENTS.md content, `.claude/rules`,
agent-loaded reference/context docs, pointer lines, doc-plus-pointer extraction — has an
authoring-time doctrine home that actually fires at that moment, inlines the adapted doctrine
(pointer wording, information hierarchy + co-location, completion criteria, split-by-sequence,
leading words + negation, two loads), and points at the audit siblings instead of restating
them.

### Constraints

- Model-invoked (`disable-model-invocation: false`); NO forcing hook — trigger reliability is a
  first-class design constraint enforced by evals, not by a hook (user-decided; hook ruled
  probable overengineering).
- Non-trigger fence (route-away): SKILL.md authoring → `playbooks:skill-authoring` +
  `skill-quality:check`; audit requests → the docs-hygiene audit siblings; human-facing docs
  (human READMEs, changelogs) → out of scope.
- Encapsulation: point at `audit-progressive-disclosure` (tier model, pointer-quality),
  `extract-ssot`, `audit-derivability`, `domain-driven-design:curate-language`; inline only the
  adapted doctrine.
- Naming grammar: imperative verb + qualifier (`write-for-agents`); no frontmatter `name`.
- Description passes `skill-quality:check listing-budget`; no upstream provenance prose in the
  skill body (SSOT decomposition table is the provenance record).
- Lane discipline: this lane implements nothing — the two filed issues carry the build through
  the normal pipeline.

### Acceptance criteria

- [ ] `plugins/docs-hygiene/skills/write-for-agents/` exists, model-invoked, body covering:
  context-pointer wording (cover the branches, front-load the leading word); information
  hierarchy (steps vs reference, co-location, sprawl); completion criteria (clarity vs demand,
  premature completion, post-completion steps, legwork); when-to-split by sequence
  (by-invocation split points at lane 8's rubric once it exists); leading words + negation
  (prompt the positive); two loads (context + cognitive). Settled by: the merged skill diff.
- [ ] Trigger families in the description: CLAUDE.md/AGENTS.md content edits, `.claude/rules`
  writing, agent-consumed reference/context docs, pointer-line adds, doc-plus-pointer
  extraction. Settled by: the shipped `evals/evals.json` suite — every positive case fires the
  skill, every negative control (audit phrasing, "create a skill", human-README writing) does
  not. This criterion was drafted naming `claude plugin eval`; the skill shipped in #3003 with
  this marketplace's own eval format, which `MIGRATION-PLAYBOOK.md` "Evals" explains is
  `skill-creator`'s and not that command's, and which nothing executes — so the suite is a
  written specification checked by `check-evals-quality.sh`, exercised by hand per that
  section's recipe, rather than a pass/fail gate on the implementation PR.
- [ ] Scope statement grounded in the verified auto-read enumeration (research artifact in the
  topic memory slice, adapted into the skill's reference table). Settled by: the reference file
  citing the enumeration's surfaces.
- [ ] PLUGIN-PHILOSOPHY Instruction economy carries a one-line cognitive-load cross-reference to
  the skill. Settled by: the philosophy diff.
- [ ] `skill-quality:check` carries a completion-criteria criterion and a pointer so skill
  authors reach the doctrine. Settled by: the skill-quality diff (second issue).
- [ ] SSOT decomposition-table verdicts updated (gaps 1–2 → adopted; leading-words strand
  retires on merge). Settled by: `docs/upstream/mattpocock-skills.md` diff.

### Captured assumptions

- `docs-hygiene` is the right home: write-side complement to seven audit/transform siblings;
  pointers stay intra-plugin. (Round 1, user-confirmed.)
- The research enumeration is additive to scope, never scope-changing — scope is already "any
  agent-consumed markdown"; the enumeration grounds the high-value core and the reference table.
- Two-loads doctrine OPERATES in the skill; the philosophy gets only a cross-reference line.

### Out-of-scope

- Skill-file authoring doctrine (incumbents own it; fence routes away).
- Invocation-mode rubric (lane 8, #2910) and cross-skill invocation phrasing (lane 6, #2904).
- Implementing any of the above in the lane session itself.

### Deferred questions

*(none — all twelve interview questions answered; the auto-read enumeration is a fact task
delegated to the research artifact, not a deferred decision)*

## Plan

*(empty — `/planning:plan` fills this when an implementation issue is picked up, if the
implementing session needs more than the Brief)*
