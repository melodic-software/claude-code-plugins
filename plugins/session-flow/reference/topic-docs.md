# Topic-docs placement — where session-flow artifacts land

How `/session-flow:handoff`, `/session-flow:workflow`, `/session-flow:retro`, and
`/session-flow:running-retro` resolve where session save-points and ledgers land in a consuming
repo. These skills read this one document; none bakes its own paths.

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
| `<TS>-running-retro-<topic>.md` cumulative ledger (running-retro skill) | `<memory_dir>/running-retros/` (default `.work/running-retros/`) — never committed. The axis is the session, like handoffs (`running-retros` is a reserved first-level name under the memory root); lifecycle is like the workflow checklist — one stable file per session chain, appended across checkpoints rather than a new file per invocation |

Timestamps are ISO-basic UTC `YYYYMMDDTHHMMSSZ` per the contract's filename spec. The memory root
is configurable via the concern file's `memory_dir` key; session-flow never writes the contract
tier.

All three artifacts are memory-tier and therefore checkout-local (contract ≥ 2.0.0): a handoff
written in one worktree is invisible to a session resuming in another. The workflow checklist is a
stage ledger the contract's `.worktreeinclude` template carries into new worktrees where the
consuming repo materializes it; handoffs and running-retro ledgers are session-scoped and
deliberately not carried.

## Resolution and runtime guards

The contract owns both, identically for every implementer — apply its "Resolution order"
and "Runtime guards" sections as written (the five-rung order with its no-project-root
branch, the once-per-session self-ignore guard on the resolved memory root, the
never-edit-the-consumer's-root-`.gitignore` rule). This binding adds only the
plugin-specific application detail: session-flow's no-project-root non-interactive
fallback lands handoffs under `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` with the
absolute path announced prominently and nothing persisted.
