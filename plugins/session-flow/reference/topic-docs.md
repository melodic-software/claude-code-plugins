# Topic-docs placement — where session-flow artifacts land

How `/session-flow:handoff`, `/session-flow:workflow`, and `/session-flow:retro` resolve where
session save-points land in a consuming repo. These skills read this one document; none bakes its
own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, and lifecycle; this document binds
this plugin's artifacts to it.

## What this plugin writes

Session-flow writes **memory tier only**, into the concern-scoped handoffs directory — the axis is
the session, not a topic, so these files sit outside topic slices (`handoffs` is a reserved
first-level name under the memory root):

| Artifact | Location |
|---|---|
| `<TS>-handoff-<topic>.md` save-points (handoff skill) | `<memory_dir>/handoffs/` (default `.work/handoffs/`) — never committed |
| `workflow-checklist.md` (workflow skill) | same directory — the two skills share one save-point surface |

Timestamps are ISO-basic UTC `YYYYMMDDTHHMMSSZ` per the contract's filename spec. The memory root
is configurable via the concern file's `memory_dir` key; session-flow never writes the contract
tier.

## Resolution (earlier wins)

1. `.claude/topic-docs.yaml` present → use its `memory_dir`.
2. A save-point / work-journal convention declared in the consumer's `CLAUDE.md` /
   `.claude/rules` → use it, and offer to persist it into the concern file.
3. Legacy `.claude/handoffs/` content exists → **old pins until migrated** (below).
4. The documented default: `.work/handoffs/`.

**No project root** (no git toplevel or project marker): interactive → ask (current directory or an
explicit path); non-interactive → `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` with the absolute
path announced prominently and nothing persisted.

## Dual-read window and legacy grace

- **Reading the handoff chain** (resume, retro `--chain-from`, prior-handoff discovery): check
  `<memory_dir>/handoffs/` first; when empty, fall back to legacy `.claude/handoffs/` and emit a
  one-line deprecation note.
- **Writes** always target the new location, EXCEPT when legacy `.claude/handoffs/` content exists
  and the consumer hasn't migrated — then old pins applies: operate **wholly** on
  `.claude/handoffs/` (reads AND writes) and emit the deprecation notice with a guarded migration
  command. Never dual-write; never split one chain across roots.
- Dual-read and the legacy fallback are removed at this plugin's next major version.

## Runtime guards

- **Self-ignore guard:** every memory-tier write verifies the memory root (`.work/`) contains a
  `.gitignore` with `*`, creating it (announced) when absent — fresh clones heal on first write.
  The guard applies only to the new location; legacy `.claude/handoffs/` writes under old pins are
  left as-is.
- No session-flow skill ever edits the consumer's root `.gitignore`.
