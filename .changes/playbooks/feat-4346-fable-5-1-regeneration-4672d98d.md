---
bump: minor
---

### Changed

- **The fable-5 doctrine is Claude Fable 5.1's.** Every line of the skill body and its thirteen chapters was kept, rewritten or removed by a Fable 5.1 session, and the pack names Fable 5.1 as its author in the skill description, body, README, update skill and plugin description. The deltas the retired Fable 5.1 adaptation chapter carried now live in the owning chapters: tool-call batching on every round in `execution.md`, targeted edits and tests sized to the task in `execution.md`, progress lines, whole-turn closing messages, plain-clause density and quotation marking in `communication.md`, the low-effort recall rule in `calibration.md`, and the lead-keeps-working pointer in `orchestration.md`, each with a pointer record. The verification chapter gains an above-the-floor move: an independent oracle (reference implementation, brute-force cross-check, or spec-driven fuzzer) run on randomized inputs where a specification allows one ([#4346](https://github.com/melodic-software/claude-code-plugins/issues/4346)).
- **Meta-rule 3 routes from Fable 5.1.** A Fable 5.1 session reads no adaptation chapter, and neither does a Fable 5 session, since the documented Fable 5.1 differences are matters of degree in tendencies the doctrine already counters and none reverses a Fable 5 behavior; the record beside it names the guide and its recheck trigger. The current-model list is Opus 5.5, Sonnet 5.5 and Haiku 5.5; the fallback-only list is unchanged. The Fable 5 system card citation is dropped: model-config owns fallback behavior. The six remaining adaptation chapters are baselined against the new author, and the Opus 4.8 chapter's Fable-behavior pointers move to the Fable 5.1 guide where it has the section.
- **Three verification records re-derived.** The calibration chapter's thinking-table pointer, the context-economy chapter's keep-all thinking record (now against Claude Code 2.1.310) and every record in the API chapter carry fresh as-of dates from raw-markdown re-reads.
- **The API chapter widens to request assembly.** `reference/prompt-caching.md` gains "Conversation history", "Forced tool use" and "Effort against model choice" sections, taking the API-side rows the retired chapter held.
- The fable-5 evals assert the new routing: a Fable 5.1 session and a Fable 5 session each read no adaptation chapter; the Sonnet 5.5 and Haiku 5.5 routing cases no longer name the retired file. Eleven `claude plugin eval` outcome cases and a frozen trigger probe set are added for the rewrite measurement.

### Removed

- `reference/model-adaptation/fable-5-1.md`. Nothing in it survives only as a patch over the doctrine; its sections were folded, moved or dropped as the Changed entry lists.
