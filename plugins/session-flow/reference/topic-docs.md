# Topic-docs placement — where session-flow artifacts land

How `/session-flow:handoff`, `/session-flow:workflow`, and `/session-flow:retro` resolve where
session save-points land in a consuming repo. These skills read this one document; none bakes its
own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, and lifecycle; this document binds
this plugin's artifacts to it.

## What this plugin writes

Session-flow writes **memory tier only**:

| Artifact | Location |
|---|---|
| `<TS>-handoff-<topic>.md` save-points (handoff skill) | `<memory_dir>/handoffs/` (default `.work/handoffs/`) — never committed. The axis is the session, not a topic, so save-points sit outside topic slices (`handoffs` is a reserved first-level name under the memory root) |
| `workflow-checklist.md` (workflow skill) | `<memory_dir>/<slug>/` (default `.work/<slug>/`) — the topic's per-slice stage ledger, never committed. Its axis is the topic: a fixed filename in the shared handoffs directory would clobber across two in-flight topics |

Timestamps are ISO-basic UTC `YYYYMMDDTHHMMSSZ` per the contract's filename spec. The memory root
is configurable via the concern file's `memory_dir` key; session-flow never writes the contract
tier.

## Resolution (earlier wins)

1. `.claude/topic-docs.yaml` present → use its `memory_dir`.
2. A save-point / work-journal convention declared in the consumer's `CLAUDE.md` /
   `.claude/rules` → use it, and offer to persist it into the concern file.
3. Legacy `.claude/handoffs/` content exists for the current slice → **old pins until migrated**
   (below). The legacy probe lives inside this rung: a concern-file hit at rung 1 short-circuits
   it, and a populated new home for the current slice proves the slice isn't pinned — skip the
   probe.
4. The documented default memory root: `.work` (save-points in `.work/handoffs/`, the workflow
   checklist in `.work/<slug>/`).

**No project root** (no git toplevel or project marker): interactive → ask (current directory or an
explicit path); non-interactive → `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` with the absolute
path announced prominently and nothing persisted.

## Dual-read window and legacy grace

This binding applies the contract's grace algorithm (the convention's "Deprecation and migration")
with slice axis = the handoff chain (save-points) or the topic slug (the workflow checklist), and
legacy root = `.claude/handoffs/`:

- **Short-circuits:** a populated new home for the current slice (`<memory_dir>/handoffs/` holding
  save-points; the topic's `<memory_dir>/<slug>/workflow-checklist.md` existing) skips the legacy
  probe entirely — the slice isn't pinned.
- **Reading the handoff chain** (resume, retro `--chain-from`, prior-handoff discovery): check
  `<memory_dir>/handoffs/` first; only when empty, fall back to legacy `.claude/handoffs/` and emit
  a one-line deprecation note.
- **Writes** always target the new location, EXCEPT when legacy `.claude/handoffs/` content exists
  for the current slice and the consumer hasn't migrated — then old pins applies: operate
  **wholly** on `.claude/handoffs/` (reads AND writes) and emit the deprecation notice with a
  guarded migration command. Never dual-write; never split one slice across roots.
- Dual-read and the legacy fallback are removed at this plugin's next major version.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory
  root** (whatever `memory_dir` names — never a hardcoded `.work`) contains a `.gitignore` with
  `*`, creating it (announced) when absent — fresh clones heal on first write. Once per session,
  per the contract. The guard applies only to the new location; legacy `.claude/handoffs/` writes
  under old pins are left as-is.
- No session-flow skill ever edits the consumer's root `.gitignore`.
