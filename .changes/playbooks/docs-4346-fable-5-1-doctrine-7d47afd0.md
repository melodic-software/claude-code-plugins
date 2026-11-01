---
bump: minor
---

### Changed

- `/playbooks:fable-5` is re-authored by Claude Fable 5.1 ([#4346](https://github.com/melodic-software/claude-code-plugins/issues/4346)). The skill body names it as the author; meta-rule 3 routes "if you are not Claude Fable 5.1", states that Claude Fable 5 and any later Fable version read no adaptation chapter, and points at the model-config fallback sections in place of the Fable 5 system card. The Fable 5.1 guide's deltas are folded into their owning chapters as model-neutral doctrine with pointer records: per-round batching, targeted edits and the committed-tests clause (execution); a density, formatting and quotation section, the long-run opening and closing lines, and the prompt-authoring note on progress updates (communication); low-effort recall and the per-model effort sweep (calibration); the compaction-summary instruction (context-economy); classifier refusals as a fourth failure kind (recovery); the independent-oracle check above the adversarial self-review floor (verification); the lead-keeps-working pointer (orchestration).
- The six remaining adaptation chapters name Claude Fable 5.1 as the author, and each Sources section records the 2026-11-01 recheck of its deltas against the re-authored doctrine; the Opus 4.8 "Behaviors to emulate deliberately" section keeps its Fable 5 guide pointers under a dated record pointing at the Fable 5.1 guide.
- The calibration chapter's thinking-table pointer, the context-economy keep-all record (now against Claude Code 2.1.316) and every row of `reference/prompt-caching.md` are re-derived with 2026-11-01 records; the prompt-caching reference gains a model-neutral "Request assembly" section carrying the practice the retired chapter stated API-side, with per-model facts left at the pointers.
- The fable-5 evals route "fable 5.1 adaptation" and a Fable 5.1 arm to no chapter, "fable 5 adaptation" and a later Fable version to no chapter, and a fallback from Fable 5.1 to Opus 5 or Opus 4.8 to that model's chapter.

### Removed

- `reference/model-adaptation/fable-5-1.md`: the doctrine is Fable 5.1's own, so its session-side deltas are doctrine and its API-side rules live in the prompt-caching reference.
