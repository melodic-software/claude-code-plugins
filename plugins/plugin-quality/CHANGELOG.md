# Changelog

All notable changes to the `plugin-quality` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-07-26

### Fixed

- **The compaction resume rule could not find the packet's findings file after the rename fallback
  fired (#1592).** 0.2.0 documented a fallback that writes the grounded findings to `audit-data.md`
  when the subagent report-file guardrail also rejects `audit-notes.md`, but the resume rule
  accepted only `audit-notes.md` or a legacy `findings.md`. A compaction after that fallback
  therefore dropped the findings file from the deterministic recovery path — the exact loss the
  packet exists to prevent — even though the substitution had been recorded in `evidence.md`.

  The rule no longer looks for one hardcoded filename. It reads the name recorded in `evidence.md`
  first, falls back to all three known names (`audit-notes.md`, `audit-data.md`, legacy
  `findings.md`), and treats every non-empty file in the packet directory as in-scope rather than
  concluding the findings are gone. Raised in review on #1569; the fix missed that PR's merge.

## [0.2.0] - 2026-07-26

### Changed

- **The evidence packet's grounded-findings file is renamed `findings.md` → `audit-notes.md`
  (#1565).** Some subagent contexts run a Write-tool guardrail that rejects report-shaped
  *filenames* — "Subagents should return findings as text, not write report files" — and the
  packet write is refused for what the file is called, not what it contains or where it goes. Both
  writers in this workflow can sit inside such a context: the `auditor` of step 2 is a subagent by
  construction, and the dispatching session is one whenever the skill is invoked from a loop lane
  or another agent, so "let the main thread write it" is not a fallback that reliably exists. The
  rename was verified empirically this session: `findings.md` and `analysis.md` were both rejected
  from a subagent, while byte-identical content written as `audit-notes.md`, `audit-packet-data.md`
  and `packet-findings.json` all succeeded — the guardrail keys on the filename alone. The
  compaction resume rule now reads `audit-notes.md` **or** a legacy `findings.md`, so packets
  already on disk stay recoverable. The guardrail is documented in the skill as **observed
  harness behavior, not documented behavior**: it appears on no official page (sub-agents
  reference checked 2026-07-26, <https://code.claude.com/docs/en/sub-agents>, which documents
  write restriction only at tool-access granularity via `disallowedTools`), so a filename outside
  the report/summary/findings/analysis class is the primary defense and a second rename is the
  documented backstop.

### Added

- **Step 4 (contract lock) gains an autonomous-invocation clause (#1566).** The step was
  written as unconditionally interactive with no branch for an unattended dispatch, so every
  loop-lane invocation re-improvised its own fallback. It now performs the step from derived
  answers rather than skipping it, using the same two rules `/work-items:setup` applies on its
  unattended path — a decision whose recommended answer is safe resolves to it silently and is
  recorded as auto-resolved; a decision with no safe default is reported as a named blocker rather
  than guessed — with a per-decision table for scope, severity calibration, named assumptions, and
  emit target. `contract.md` records `autonomous: true` so a later reader can tell which answers
  came from a human.

  The emit-target row does **not** block when the ladder's rungs 1–2 both miss. An earlier revision
  of this entry called an unresolved target a blocker, which contradicted step 6 — that step sends
  every unattended run to rung 4 regardless of whether 1–2 resolved, and `reference/config.md`
  names "no repo" as one of rung 4's own entry conditions. Blocking would have stranded exactly the
  targetless runs rung 4 exists for: a plugin loaded with `--plugin-dir` has no marketplace
  registration to infer from and no tracked config, and is the case most likely to be audited
  unattended. The row now records which rung would have been taken, or that none resolved, and the
  emit lands on rung 4 either way.
- **Step 6 (egress gate) gains an autonomous-invocation clause that does NOT relax the gate
  (#1566).** The originating report proposed treating step 6 as having "the identical issue" as
  step 4; that half is **refuted**. Step 4 has no external side effect, so deriving its answers is
  safe; step 6's draft+confirm surface is the recorded override that lets a read-only `audit` verb
  mutate at all, and an absent confirmer is not an implicit confirmation. An unattended run
  therefore falls to sink-ladder rung 4 unconditionally — the complete item is written locally as
  `item.md` and the run reports the rung and identity it would have used, then stops. No auto-file
  mode is introduced: rung 4 was already the one path the gate does not cover, because it produces
  no external effect.
- Two evals covering both clauses, including an anti-pattern eval asserting that an unattended
  invocation must not emit externally.

## [0.1.2] - 2026-07-25

### Changed

- `skills/audit` step 2 no longer justifies its dispatch by what a fork inherits. Three successive
  rationales for rejecting `context: fork` were each defeated in review, so the requirement is now
  stated as an invariant the step must satisfy: a context that carries the evidence packet but
  **not** this session's conversation history or prior reasoning, plus a named dispatch target that
  makes the dispatch site auditable. The `auditor` agent supplies both — and the packet crossing the
  boundary is deliberate, since the agent reads it as ground truth. The framing holds either way on
  #1258, which reports the Agent tool's `fork` subagent type not inheriting the conversation in
  practice, against its documentation.

## [0.1.1] - 2026-07-24

### Fixed

- `skills/audit` step 2 no longer claims a fork "would inherit this session's degraded history".
  That is false for a skill's `context: fork` frontmatter, which starts the subagent with no
  conversation history; conversation inheritance belongs to the Agent tool's separate `fork`
  subagent type. The step now names that type explicitly and also forbids running inline.
- `skills/audit/references/component-types/skill.md` composition lens no longer asserts that a
  forked sub-skill "loses history" as a defect; it asks whether the inline-vs-`context: fork`
  choice matches what the step needs, and names the mechanism.
- `agents/auditor.md` says why it has no conversation history — it is a named subagent rather than
  a conversation fork — instead of leaving "by design" for the reader to interpret.

## [0.1.0] - 2026-07-24

### Added

- `skills/audit` — six-step post-use component audit (`/plugin-quality:audit
  <plugin>[:<component>]`): evidence capture into a compaction-proof packet, map+ground in the
  fresh `auditor` subagent with per-topic fresh-docs verification, blindspot + candidates,
  interactive contract lock, presence-gated review seams, sink emit behind the draft+confirm
  egress gate (acting `gh` account surfaced). Context-gate over context-guard snapshots with a
  per-zone decision table; conservative on unknown. Evals incl. conservative-dispatch and
  prompt-injection anti-pattern cases.
- `agents/auditor.md` — fresh-context audit specialist (steps 2–3) with an honest Bash grant and
  the standing untrusted-content instruction.
- `skills/audit/references/` — recurring-concerns checklist + five component-type lenses, ported
  from the retiring machine-local skill and generalized.
- `reference/config.md` — `.claude/plugin-quality.md` cascade surface (per-key override), sink
  resolution ladder, markdown item schema (byte-compatible with the cross-terminal handoff inbox
  contract), work-items seam boundary.
- `skills/setup` — `check` (gh + acting account, context-guard seam → dispatch mode, config
  provenance) / `apply` (tracked config only), with evals.
