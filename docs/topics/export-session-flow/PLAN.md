# export-session-flow

## Brief

### TLDR

- Three session-flow skills (`clean-stop`, `handoff` on its prompt-only path, `retro`) gain a one-line suggestion to run the built-in `/export` at their natural decision points, closing the one durability gap the artifact layer leaves open: the conversation itself.
- No new skill, no automation, no transcript parsing. `/export` is user-invoked only (not Skill-invocable, and confirmed unavailable headless), so the shape is a suggestion the user acts on, mirroring the orient-vs-`/recap` complement pattern.
- Suggested destination convention: `<memory_dir>/exports/<timestamp>-<topic>.txt` (default `.work/exports/`), kept out of commits by the memory root's self-ignoring `.gitignore`, which the suggesting skill verifies or creates before presenting the command. `exports` joins the convention's reserved first-level names so a topic slug cannot collide with it. Nothing records or verifies that the export happened.
- Sharing/presenting conversations, redaction tooling, a `SessionEnd`-hook archive lane for cloud sessions, and a dedicated archive skill are all explicitly deferred, not silently dropped.

### Goal

A user ending, handing off, or retrospecting a session they care about is reminded, at exactly the moment it is cheap, that the conversation has no durable home (transcripts are retention-swept at `cleanupPeriodDays`, default 30 days, and prompt-only handoffs live only in the transcript), and is handed a copy-paste-ready `/export` line with a sane destination. Nothing else changes: no new components, no new state, no new parsing of the officially unstable transcript JSONL.

### Constraints

- Built-in commands are not Skill-invocable; the suggestion is text the user acts on, never an invocation the skill performs (per the repo doctrine stated in `plugins/session-flow/skills/orient/SKILL.md`).
- The repo narrows transcript-JSONL touching rather than widening it (`reconcile`'s parse ban, `context-guard`'s capture rejection); this change adds no JSONL consumer.
- Suggestion text carries one honest sentence that `/export` does not exist in cloud/headless sessions (empirically confirmed on the current CLI: `/export` is unavailable under `-p`).
- Exports stay memory-tier and no committed artifact ever points at an export file. The self-gitignore claim is guarded, not assumed: per the topic-docs runtime guard, the skill presenting the suggestion first verifies the resolved memory root contains a `.gitignore` with `*`, creating it (announced) when absent, so a fresh clone cannot stage a secret-laden export.
- `exports` becomes a reserved first-level name under the memory root in `docs/conventions/topic-docs/README.md` (and its schema where applicable), so a planning topic whose slug derives to `exports` cannot collide with the export directory.
- The suggestion always names an explicit destination path, so the unresearched no-argument dialog default of `/export` is never load-bearing.
- Repo gates for touched skills apply: plugin version bump + changelog, eval updates where assertions change, prose rules (`ai-slop` audit) on edited instruction surfaces.
- Before any routing phrase for `/export` is baked into skill text, the native-overlap registry (canonical-pairs -> `records.json`) gains its `/export` row, since the command is currently absent from the repo's recorded knowledge of native surfaces.

### Acceptance criteria

- `plugins/session-flow/skills/clean-stop/SKILL.md`: the durability checklist names the conversation as a non-durable item and carries the one-line `/export <memory_dir>/exports/<timestamp>-<topic>.txt` suggestion with the cloud-session caveat. Because clean-stop's documented cases include the machine going away, its variant of the suggestion also notes that the destination is machine-local and recommends an off-machine copy (or a user-chosen durable path) when the machine itself is at risk.
- `plugins/session-flow/skills/handoff/SKILL.md`: the prompt-only path carries the same suggestion, framed as "this handoff lives only in the transcript; export it if it must outlive the retention sweep".
- `plugins/session-flow/skills/retro/SKILL.md`: carries the suggestion for sessions worth retrospecting, without altering the parser or metrics flow.
- All three suggestions are one to two lines each, name the same destination convention, and do not claim the export happened or record any pointer to it.
- The native-overlap registry contains a human-gated `/export` row before the skill edits merge.
- `docs/conventions/topic-docs/README.md` (and schema where applicable) lists `exports` among the reserved first-level names under the memory root, landing with or before the skill edits.
- Each skill's suggestion text (or the step presenting it) runs the memory-root self-ignore guard before the export path is offered.
- session-flow plugin version bumped with a changelog entry; evals for the three skills updated only where existing assertions would now be false.
- No file outside `plugins/session-flow/`, the overlap registry, and the topic-docs convention's reserved-names entry changes (this Brief and its slice excepted).

### Captured assumptions

- `/export` behavior as researched at CLI 2.1.241 (plain text only, optional filename argument, extension preserved, output outside the retention sweep, unavailable headless) holds at implementation time; re-check the changelog if the CLI has moved substantially.
- The `.work/` memory root is normally self-gitignored by the topic-docs convention; the guard constraint above covers the fresh-clone case where it is not yet.
- Exact wording and in-file placement of each suggestion line is implementation latitude within the acceptance criteria; it is not a deferred decision.

### Out-of-scope

- Sharing or presenting conversations (and any redaction/scrub tooling). Deferred until the need materializes; the destination convention is the only forward provision.
- A `SessionEnd` hook copying `transcript_path` for cloud/automation coverage. It is the only seam for headless sessions, but hooks default to REJECT under the repo's automation-gaps posture and need their own argued verdict.
- A dedicated `session-flow:archive` skill or any consume-side behavior (indexing, retro fallback reading exports, frontmatter pointers).
- Any change to `running-retro`, `find-handoff`, or other session-flow skills.

### Deferred questions

- Q2 — does the sharing/presenting use case ever materialize, and with what redaction posture? Defer until the need arises; **arbiter: USER-RESERVED**
- Q3 — should the `SessionEnd`-hook archive lane be proposed for cloud sessions? Defer until an automation-gaps audit verdict exists; **arbiter: USER-RESERVED**

## Plan

<!-- empty — populated by /planning:plan -->
