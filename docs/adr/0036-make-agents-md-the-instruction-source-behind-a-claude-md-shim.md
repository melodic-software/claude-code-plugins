# Make AGENTS.md the instruction source, behind a one-line CLAUDE.md shim

- Status: accepted
- Date: 2026-09-21

## Context

Ten melodic-software repositories carried their agent instructions in `CLAUDE.md`, a file only
Claude Code reads, while Codex, Cursor and the rest read `AGENTS.md`. Claude Code can read
`AGENTS.md` for itself from a recent CLI version, but only under conditions no repository controls
(both recorded under "Why" below), so moving the content across without deciding how it loads
risks instructions that silently stop loading.

## Decision

`AGENTS.md` is the one tool-agnostic instruction source in every in-scope repository, root and
nested. Every `CLAUDE.md` beside one is exactly the single line `@AGENTS.md`, with no content of
its own; Claude-specific text lives in `.claude/rules/`.

The shims stay until all four cutover conditions hold. They are graded, each with its evidence, by
`/instruction-placement:migrate cutover-check`; the conditions are defined in the "The cutover:
`cutover-check`, then `remove-shims`" section of
`plugins/instruction-placement/skills/migrate/SKILL.md`, and are the remote flag, CI, the local
canary, and path detection. `/instruction-placement:migrate remove-shims` takes root and nested
shims out together once they all hold. The check reruns monthly, and on any Claude Code release
touching instruction files, as
<https://github.com/melodic-software/claude-code-plugins/issues/4281>.

## Why

Direct reading is conditional in ways a repository cannot fix from inside: it is gated on a remote
feature flag whose code default is false, is suppressed by any `CLAUDE.md` at or above the working
directory, needs CLI 2.1.277 or later, and is absent from some sessions entirely. Each of those is
a four-part dated record in
`plugins/instruction-placement/skills/migrate/reference/sources.md` ("The remote flag, and how its
code default is read", "The documented feature-flag dependency", "The minimum CLI version"), and
the loading rule itself is the record under "Why the shim stays" in that skill's `SKILL.md`.

The shim costs about 55 tokens per session, never makes Claude read the file twice, and loads in
the conditions that record lists as unavailable for direct reading (all three stated under "Why the
shim stays"). It also keeps what direct reading loses: an `AGENTS.md` read directly appears in
neither `/memory` nor the `/context` Memory files and fires no `InstructionsLoaded` hook ("What
shim removal costs"), so this repository's own load verification cannot see it ("What the loss
means for measuring the cutover"), both in the same `sources.md`. Removal is therefore a priced
decision, not tidying.

Three alternatives were rejected, each with the fact that would flip it:

| Rejected | Why | What would flip it |
|---|---|---|
| Native only: delete `CLAUDE.md` now | With the flag off, a lone `AGENTS.md` loads nothing ("The remote flag, and how its code default is read"), and any `CLAUDE.md` above the working directory suppresses the read regardless ("Why the shim stays") | All four graded conditions report `[MET]` |
| The `claude-md-and-agents-md` both-files setting | A user, `--settings` or managed setting, ignored in project and local settings, so no repository can ship it ("Why the shim stays"); never adopted or run as a convention | The setting becomes readable from project or local settings |
| A common-ancestor `D:/repos/AGENTS.md` | No repository versions it, and it misses every worktree checked out outside that tree | Claude Code reads a versioned org-level tier above the repository |

## Consequences

- Both files exist in every in-scope directory, and they move together: "Why the shim stays" has
  Claude Code attach a subdirectory's `AGENTS.md` only where no `CLAUDE.md` sits in that directory
  or above it, so a lone nested `AGENTS.md` never attaches while a root `CLAUDE.md` exists.
- Code that locates a repository root by the existence of `CLAUDE.md` works today and breaks at
  cutover. Condition 4 grades each such site against a reviewed, per-repository
  `.claude/cutover-pathdet-ack.txt`.
- Each root-to-directory `AGENTS.md` path stays under Codex's project-doc budget, which truncates
  with no error. The 32,768-byte default is `project_doc_max_bytes` in `openai/codex`
  (`codex-rs/config/defaults.toml`).
- Shim removal is blocked until the installed `claude-memory` and `instruction-placement` plugins
  carry the corrected doctrine; an older cached build advises a de-shimmed repository straight back
  to the old shape.
