# claude-code-plugins

## Open a pull request as a draft

Open every pull request as a draft and flip it to ready when the work is done: a draft skips the
test lanes and both AI review lanes, and the flip to ready is what asks for them once.

<!-- BEGIN GENERATED: instruction-placement rules index -->

## Conventions that load on demand

Each surface below enters context automatically when Claude reads a file it covers, in subagents
as well as in the main session. The match is on the requested path, so even a read that finds no
file fires it. A surface whose trigger has not fired is simply absent, and after a compaction it
returns only when a covered file is read again. When you are working on something an entry covers
and its content is not already in context, read the file directly.

| Surface | Covers | Topic |
|---|---|---|
| `.claude/rules/ruff-pin.md` | `**/*.py` | Python linting runs through the pinned ruff wrapper, never a bare ruff on PATH |
| `.claude/rules/skill-bodies-state-current-rules.md` | `plugins/*/skills/**, plugins/*/agents/**` | Skill and agent bodies carry a four-part verification record for any volatile specific they restate, and name their successor in a `## Next` section; read before editing any skill body |
| `plugins/autonomy/AGENTS.md` | `plugins/autonomy/**` | autonomy plugin: contributor conventions |
| `plugins/machine-health/skills/audit/AGENTS.md` | `plugins/machine-health/skills/audit/**` | machine-health audit skill: contributor conventions |
| `plugins/playbooks/reference/model-adaptation/AGENTS.md` | `plugins/playbooks/reference/model-adaptation/**` | model-adaptation chapters: contributor conventions |
| `plugins/provenance/skills/audit/AGENTS.md` | `plugins/provenance/skills/audit/**` | Editing the provenance audit skill: contributor conventions |
| `plugins/work-items/skills/work-loop/AGENTS.md` | `plugins/work-items/skills/work-loop/**` | work-loop: contributor conventions |

<!-- END GENERATED: instruction-placement rules index -->
