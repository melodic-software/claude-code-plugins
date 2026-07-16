# automation-gaps — per-category gap checklists

**Hooks** — for each language with production code (`.cs`, `.py`, `.ts`, `.sh`, `.ps1`, `.md`):

- Does a PostToolUse formatter hook exist?
- Does the language's build/lint tool run fast enough for a per-edit hook (<15s)?
- Does a higher enforcement level (compiler, analyzer, build-time) already catch what the hook would catch?

**MCP Servers** — for each external service the repo interacts with:

- Is there an MCP server configured?
- Is there a CLI tool that already provides equivalent access?
- Is the service actually in use yet, or is it planned/future?

**Skills** — for each recurring workflow pattern:

- Is there a skill for it?
- How often does it occur? (check git history)
- Is there a simpler mechanism (CLI command, behavioral rule) that handles it?

**Subagents** — for each quality concern:

- Would a subagent provide value over a hook or skill?
- Does context isolation actually help?
- Is there a plugin that already provides this?

**Scheduled** — for each recurring maintenance task:

- Is it tracked in the repo's work-item tracker with a cadence?
- Does Dependabot or CI already handle it?
- Does a recurring-loop or scheduled-task mechanism provide the right durability model?
