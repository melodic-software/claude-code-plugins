# Topic-docs placement: where session-flow artifacts land

How `/session-flow:handoff`, `/session-flow:workflow`, `/session-flow:retro`, and
`/session-flow:running-retro` resolve where session save-points and ledgers land in a consuming
repo. These skills read this one document; none bakes its own paths. The read-only
`/session-flow:orient` and `/session-flow:find-handoff` skills also read this binding to *locate*
those artifacts (orient for its briefing, find-handoff to resolve the handoffs dir it recovers
from). They resolve the paths, never write them.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, and lifecycle; this document binds
this plugin's artifacts to it.

## What this plugin writes

Session-flow writes **memory tier only**:

| Artifact | Location |
|---|---|
| `<TS>-handoff-<topic>.md` save-points (handoff skill) | `<memory_dir>/handoffs/` (default `.work/handoffs/`), never committed. The axis is the session, not a topic, so save-points sit outside topic slices (`handoffs` is a reserved first-level name under the memory root) |
| `workflow-checklist.md` (workflow skill) | `<memory_dir>/<slug>/` (default `.work/<slug>/`), the topic's per-slice stage ledger, never committed. Its axis is the topic: a fixed filename in the shared handoffs directory would clobber across two in-flight topics |
| `<TS>-running-retro-<topic>.md` cumulative ledger (running-retro skill) | `<memory_dir>/running-retros/` (default `.work/running-retros/`), never committed. The axis is the session, like handoffs (`running-retros` is a reserved first-level name under the memory root). Lifecycle: **one file per session, appended.** Later checkpoints discover this session's file by matching the current `session_id` in frontmatter (never a new file per checkpoint); resumed sessions in a handoff chain open their own ledger and link back via `previous_running_retro` / `previous_session_id` pointers the skill walks (never the parser), forming the cumulative running-retro chain |

Timestamps are ISO-basic UTC `YYYYMMDDTHHMMSSZ` per the contract's filename spec. The memory root
is configurable via the concern file's `memory_dir` key; session-flow never writes the contract
tier.

The writers never delete, so the `tidy-work` skill owns the lifecycle (`scripts/tidy_work.py`).
`report` inventories the memory root and `~/.work` by age, size, and kind (handoff, running-retro,
slice, checklist, scratch, unknown) and marks each item in flight or stale. `normalize` moves a
handoff or running-retro file that sits in the wrong directory into `handoffs/` or
`running-retros/`; it never deletes and refuses to overwrite. `clean` removes only items of a known
kind that are not in flight. Both are dry runs that print exact absolute paths until `--apply`. An
unknown item, such as another tool's own folder, is always reported and always kept. An item is in
flight when its frontmatter links an open or unknown-state issue or PR, it changed within the window
(default 14 days), a later handoff names it, or its checklist has an unfinished stage.

The running-retro **detached observer** ([`observer.md`](./observer.md)) writes autonomous post-end
findings to that same `running-retros/` ledger (matched by `session_id`), so the autonomous and
in-session checkpoints share one file per session. Its intermediate distilled observations are NOT a
memory-tier artifact: they are transient, machine-local plugin state under
`${CLAUDE_PLUGIN_DATA}/session-flow-observer/`, deleted after the analysis run consumes them, and
never committed; only the redacted findings block reaches the ledger. Before its first ledger
write the observer runs the contract's self-ignore guard on the resolved memory root, ensuring
`<memory_dir>/.gitignore` contains a bare `*` (creating or amending it as needed) so the memory-tier
output is never committed, and, when the memory root is itself a repo root, refuses and does not write
the ledger there; it never edits the consumer's
root `.gitignore`.

All three artifacts are memory-tier and therefore checkout-local (contract ≥ 2.0.0): a handoff
written in one worktree is invisible to a session resuming in another. The workflow checklist is a
stage ledger the contract's `.worktreeinclude` template carries into new worktrees where the
consuming repo materializes it; handoffs and running-retro ledgers are session-scoped and
deliberately not carried.

## Resolution and runtime guards

The contract owns both, identically for every implementer. Apply its "Resolution order"
and "Runtime guards" sections as written (the five-rung order with its no-project-root
branch, the once-per-session self-ignore guard on the resolved memory root, the
never-edit-the-consumer's-root-`.gitignore` rule). This binding adds only the
plugin-specific application detail: session-flow's no-project-root non-interactive
fallback writes the handoff file under `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` and
announces its absolute path prominently. What is not persisted there is the resolution:
no `.claude/topic-docs.yaml` is written for the fallback. Bash-tool commands carry no
`CLAUDE_PLUGIN_DATA`, so on that branch the handoff step omits `--memory-dir` and
`save_point.py new` resolves the plugin data dir itself
([`structure.md`](structure.md) "Verification record: plugin data dir").
