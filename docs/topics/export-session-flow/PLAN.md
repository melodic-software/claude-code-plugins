# export-session-flow

## Brief

### TLDR

- Three session-flow skills (`clean-stop`, `handoff` on its prompt-only path, `retro`) gain a one-line suggestion to run the built-in `/export` at their natural decision points, closing the one durability gap the artifact layer leaves open: the conversation itself.
- No new skill, no automation, no transcript parsing. `/export` is user-invoked only (not Skill-invocable, and confirmed unavailable headless), so the shape is a suggestion the user acts on, mirroring the orient-vs-`/recap` complement pattern.
- Suggested destination convention: `<memory_dir>/exports/<timestamp>-<topic>.txt` (default `.work/exports/`), which is self-gitignored so secret-laden exports cannot reach commits. Nothing records or verifies that the export happened.
- Sharing/presenting conversations, redaction tooling, a `SessionEnd`-hook archive lane for cloud sessions, and a dedicated archive skill are all explicitly deferred, not silently dropped.

### Goal

A user ending, handing off, or retrospecting a session they care about is reminded, at exactly the moment it is cheap, that the conversation has no durable home (transcripts are retention-swept at `cleanupPeriodDays`, default 30 days, and prompt-only handoffs live only in the transcript), and is handed a copy-paste-ready `/export` line with a sane destination. Nothing else changes: no new components, no new state, no new parsing of the officially unstable transcript JSONL.

### Constraints

- Built-in commands are not Skill-invocable; the suggestion is text the user acts on, never an invocation the skill performs (per the repo doctrine stated in `plugins/session-flow/skills/orient/SKILL.md`).
- The repo narrows transcript-JSONL touching rather than widening it (`reconcile`'s parse ban, `context-guard`'s capture rejection); this change adds no JSONL consumer.
- Suggestion text carries one honest sentence that `/export` does not exist in cloud/headless sessions (empirically confirmed on the current CLI: `/export` is unavailable under `-p`).
- Exports stay memory-tier: `.work/` is self-gitignored, and no committed artifact ever points at an export file.
- The suggestion always names an explicit destination path, so the unresearched no-argument dialog default of `/export` is never load-bearing.
- Repo gates for touched skills apply: plugin version bump + changelog, eval updates where assertions change, prose rules (`ai-slop` audit) on edited instruction surfaces.
- Before any routing phrase for `/export` is baked into skill text, the native-overlap registry (canonical-pairs -> `records.json`) gains its `/export` row, since the command is currently absent from the repo's recorded knowledge of native surfaces.

### Acceptance criteria

- `plugins/session-flow/skills/clean-stop/SKILL.md`: the durability checklist names the conversation as a non-durable item and carries the one-line `/export <memory_dir>/exports/<timestamp>-<topic>.txt` suggestion with the cloud-session caveat.
- `plugins/session-flow/skills/handoff/SKILL.md`: the prompt-only path carries the same suggestion, framed as "this handoff lives only in the transcript; export it if it must outlive the retention sweep".
- `plugins/session-flow/skills/retro/SKILL.md`: carries the suggestion for sessions worth retrospecting, without altering the parser or metrics flow.
- All three suggestions are one to two lines each, name the same destination convention, and do not claim the export happened or record any pointer to it.
- The native-overlap registry contains a human-gated `/export` row before the skill edits merge.
- session-flow plugin version bumped with a changelog entry; evals for the three skills updated only where existing assertions would now be false.
- No file outside `plugins/session-flow/` and the overlap registry changes (this Brief and its slice excepted).

### Captured assumptions

- `/export` behavior as researched at CLI 2.1.241 (plain text only, optional filename argument, extension preserved, output outside the retention sweep, unavailable headless) holds at implementation time; re-check the changelog if the CLI has moved substantially.
- The `.work/` memory root remains self-gitignored by the topic-docs convention, so exports there cannot leak into commits.

### Out-of-scope

- Sharing or presenting conversations (and any redaction/scrub tooling). Deferred until the need materializes; the destination convention is the only forward provision.
- A `SessionEnd` hook copying `transcript_path` for cloud/automation coverage. It is the only seam for headless sessions, but hooks default to REJECT under the repo's automation-gaps posture and need their own argued verdict.
- A dedicated `session-flow:archive` skill or any consume-side behavior (indexing, retro fallback reading exports, frontmatter pointers).
- Any change to `running-retro`, `find-handoff`, or other session-flow skills.

### Deferred questions

- Q2-deferral: does the sharing/presenting use case ever materialize, and with what redaction posture? Revisit only on demand; **arbiter: USER-RESERVED**
- Q3-deferral: should the `SessionEnd`-hook archive lane be proposed for cloud sessions? Requires an automation-gaps audit verdict first; **arbiter: USER-RESERVED**
- Wording and exact placement of each suggestion line within the three SKILL.md files; **arbiter: implementation**

## Plan

<!-- empty — populated by /planning:plan -->
