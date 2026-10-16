# audit-automation-gaps: per-category gap checklists

**Hooks**: For each language with production code (`.cs`, `.py`, `.ts`, `.sh`, `.ps1`, `.md`):

- Does a formatter rewrite once per batch of edits (one `PostToolBatch` hook that sends the model nothing) and again in a git `pre-commit` hook that re-stages the files? Recommend the per-batch hook only while its median per fire stays at or under 1 s; a slower formatter goes to `pre-commit` only.
- Does a report-only check (a linter, spell checker or scanner that only prints findings) run from a per-edit `PostToolUse` hook? Never recommend one. Flag an existing one with its placement: a git `pre-commit` hook that blocks on findings in changed lines, `pre-push` when the measured run is over the commit budget but within 60 s, CI beyond that. A git hook covers every author, and the findings stop reaching the model on in-between states.
- Does the check's tool run fast enough for the git hook it would go in, judged against the consuming repo's own documented budget where it has one (see the skill's `context/hook-timing.md`)? CI still re-runs it on the change; a local pass never replaces that.
- Does a higher enforcement level (compiler, analyzer, build-time) already catch what the hook would catch?
- A reusable command is a skill, and an external-service tool is an MCP server; those stay on the checklists below. A mod, a plugin of function hooks, is the candidate only when the need goes past what a settings hook, a skill, or an MCP server can do: draw in the interface (a pane, band, status entry or toast), rewrite a prompt or model request, or read in-process session state. The verdict says so, and whoever writes it loads the built-in `plugin-authoring` skill first, because that skill carries the type declarations for the running Claude Code build.

The placement rules above, the 1 s and 60 s lines among them, are this marketplace's house rules, not upstream guidance: [check-placement](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/check-placement/README.md#the-rubric). A consuming repo that documents its own placement rules overrides them.

- **Pointer**: for what `PostToolBatch` receives and when it fires, fetch [hooks: PostToolBatch](https://code.claude.com/docs/en/hooks#posttoolbatch) live.
- **As of**: 2026-10-15
- **Recheck trigger**: that section adds a matcher or `if` support, or stops firing once per batch of parallel tool calls.

**Claim:** which needs only a mod meets. **Basis:** the "Compare mods, settings hooks, skills, and MCP servers" table in the [mods overview](https://code.claude.com/docs/en/plugins/mods/overview), fetched as raw markdown, and the `plugin-authoring` skill's "From the ask to the shape" table for status entries, toasts and tools. **As of:** 2026-10-03, Claude Code 2.1.288. **Recheck:** either "Pick it when" cell for mods or settings hooks changes, or a release lets a settings hook draw in the interface.

**MCP Servers**: For each external service the repo interacts with:

- Is there an MCP server configured?
- Is there a CLI tool that already provides equivalent access?
- Is the service actually in use yet, or is it planned/future?

**Skills**: For each recurring workflow pattern:

- Is there a skill for it?
- How often does it occur? (check git history)
- Is there a simpler mechanism (CLI command, behavioral rule) that handles it?

**Subagents**: For each quality concern:

- Would a subagent provide value over a hook or skill?
- Does context isolation actually help?
- Is there a plugin that already provides this?

**Scheduled**: For each recurring maintenance task:

- Is it tracked in the repo's work-item tracker with a cadence?
- Does Dependabot or CI already handle it?
- Does a recurring-loop or scheduled-task mechanism provide the right durability model?
