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

## Resolution (the contract's five-rung order, earlier wins)

1. `.claude/topic-docs.yaml` present → use its `memory_dir`.
2. A save-point / work-journal convention declared in the consumer's `CLAUDE.md` /
   `.claude/rules` → use it, and offer to persist it into the concern file.
3. An existing conforming layout inferred from the repo (a self-ignoring memory root holding
   save-points) → confirm with the user, persist to the concern file.
4. Ask once — one question, recommended option first; persist the answer to the concern file.
5. The documented default memory root: `.work` (save-points in `.work/handoffs/`, the workflow
   checklist in `.work/<slug>/`).

**No project root** (no git toplevel or project marker): interactive → ask (current directory or an
explicit path); non-interactive → `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` with the absolute
path announced prominently and nothing persisted.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory
  root** (whatever `memory_dir` names — never a hardcoded `.work`) contains a `.gitignore` with
  `*`, creating it (announced) when absent — fresh clones heal on first write. Once per session,
  per the contract.
- No session-flow skill ever edits the consumer's root `.gitignore`.
