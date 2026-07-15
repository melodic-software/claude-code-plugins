# Ecosystem Improvement Catalog

Taxonomy of improvements codifiable from session findings. Each category maps a finding type to a
specific ecosystem target.

**Research before recommending.** The Claude Code ecosystem evolves constantly — verify current
capabilities against current official docs (WebSearch, WebFetch, or a docs-lookup agent/MCP
server) before recommending; never recommend features from training-data assumptions.

## Placement Decision Tree

Before recommending a target, determine WHERE the finding should live. The key distinction is
**scope** — who needs this knowledge, and what happens if it is lost?

**Two scopes:**

- **project** — git-tracked in the consuming repo (`CLAUDE.md`, `.claude/rules/`,
  `.claude/skills/`, `.claude/settings.json`). Committed, shared, survives machine loss.
- **personal** — machine-local (auto-memory under the session data directory, user settings). NOT
  committed, NOT backed up. Only affects this user's sessions.

**Decision questions (ask in order, stop at first match):**

1. **Would another contributor (human or agent) on a fresh clone need this?**
   - Technical gotchas, tooling quirks, enforcement gaps, conventions → **project**
     (rules/CLAUDE.md)
   - Example: "the analyzer silently skips generated files" → the relevant `.claude/rules/` file
2. **Does it protect the accuracy or quality of a specific git-tracked artifact?**
   - Guard rails for skills, rules files, or documentation → **project** (in the artifact it
     protects)
   - Example: a source-verification guard for a skill → that skill's own SKILL.md
   - These often *look like* feedback memories ("don't do X") but are quality gates for a shared
     artifact — would a different agent on a fresh clone make the same mistake? Yes → project.
3. **Is it about how this specific user wants the agent to behave?**
   - Interaction preferences, behavioral corrections, validated approaches → **personal**
     (feedback memory)
   - Laptop dies = acceptable; the next session rediscovers preferences through interaction.
4. **Is it about this user's role, expertise, or context?**
   - User profile, domain knowledge level → **personal** (user memory); rediscoverable by asking
5. **Is it about ongoing work status, deadlines, or who's doing what?**
   - Temporal project context → **personal** (project memory)
   - Laptop dies = check git log, the issue tracker, and project boards for current state.
6. **Is it a pointer to where information lives externally?**
   - External system references → **personal** (reference memory); rediscoverable by asking

**Laptop-dies test:** if this knowledge were lost tomorrow, would the project suffer (→ commit it)
or would just this user's convenience suffer (→ memory is fine)?

**Common misplacements to watch for:**

- Technical gotchas in memory instead of rules — these affect ALL contributors, not just one user
- Convention decisions in memory instead of CLAUDE.md — if it's how the project works, commit it
- **Guard rails for skills/artifacts in feedback memory instead of the artifact itself** — if a
  correction prevents corrupting a git-tracked file, it belongs in that file, not in memory
- "Project status" memories that duplicate git-tracked content — redundant with the file itself
- Session metrics (retro scores) — personal by default; move into the repo only if the team wants
  AI quality visibility

## Memory

Personal learnings that persist across THIS USER's sessions on THIS machine. NOT committed, NOT
shared — either rediscoverable (preferences, references) or ephemeral (work status).

### When to recommend

- **Feedback memory** — the user corrected behavior, or a non-obvious approach was validated
- **User memory** — learned something about the user's role, preferences, or expertise
- **Project memory** — learned about ongoing work, deadlines, or context not in code/git
- **Reference memory** — discovered where information lives in external systems

### Format

Match the consumer's existing auto-memory conventions — read a sibling memory file first and follow
its naming, structure, and any index it maintains rather than inventing a new format.

### What NOT to save

No code patterns derivable from the codebase, no git history, no debugging recipes, no duplicates
of instruction-file content, no ephemeral task details.

## CLAUDE.md / Rules

Conventions and guidelines that should be documented.

### When to recommend

- A convention was followed implicitly but isn't documented — future sessions would rediscover it
- An existing rule was ambiguous and caused confusion — clarify it
- A rule is outdated and caused incorrect behavior — update or remove it
- A new pattern was established that should be the default going forward

### Criteria for CLAUDE.md vs rules files

| Target | Criteria |
| --- | --- |
| CLAUDE.md | Repo-wide, always-on context. Keep brief — reference, don't duplicate |
| `.claude/rules/*.md` | Scoped to file types. Detailed conventions, gotchas, examples |
| Neither | General industry knowledge the agent already follows |

### Important

Do NOT recommend content that duplicates source-of-truth files (linter configs, analyzer rule
lists, formatter settings). CLAUDE.md documents that enforcement exists; it doesn't reproduce it.

## Hooks

Automated enforcement for agentic workflow. The hook system evolves — verify supported events,
matcher syntax, and environment variables against the current hooks documentation.

### When to recommend

- A recurring mistake could be caught automatically before it happens
- A quality gate was missed that could be enforced by a hook
- A specific tool usage pattern should be blocked or warned about

### Hook events (verify the current list before recommending)

| Hook Event | Use Case | Matcher |
| --- | --- | --- |
| SessionStart | One-time setup when a session begins or resumes | startup, resume, clear, compact |
| Setup | Repo setup/maintenance runs (`--init`, `--init-only`, `--maintenance`) | init, maintenance |
| UserPromptSubmit | Inject context or validate before Claude processes a prompt | (none) |
| UserPromptExpansion | When a user-typed command expands into a prompt | command name |
| PreToolUse | Block or warn before a tool executes | tool name |
| PermissionRequest / PermissionDenied | Permission dialog appears / tool call auto-denied | tool name |
| PostToolUse | Validate output after a tool succeeds (e.g., format check) | tool name |
| PostToolUseFailure | React to failed tool calls | tool name |
| PostToolBatch | After a batch of parallel tool calls resolves | (none) |
| Notification | When Claude Code sends a notification | notification type |
| MessageDisplay | While assistant message text is displayed | (none) |
| SubagentStart / SubagentStop | When subagents spawn or finish | agent type |
| TaskCreated / TaskCompleted | Task-list lifecycle — creation and completion | (none) |
| TeammateIdle | When an agent-team teammate is about to go idle | (none) |
| Stop | When Claude finishes responding | (none) |
| StopFailure | When the turn ends due to an API error | error type |
| InstructionsLoaded | When a CLAUDE.md or rules file loads into context | session_start, nested_traversal, path_glob_match, include, compact |
| ConfigChange | When a config file changes during a session | config source |
| CwdChanged | When the working directory changes | (none) |
| FileChanged | When a watched file changes on disk | filenames to watch |
| WorktreeCreate / WorktreeRemove | Worktree lifecycle — environment setup, cleanup | (none) |
| PreCompact / PostCompact | Before / after context compaction | manual, auto (PreCompact only) |
| Elicitation / ElicitationResult | MCP server user-input requests and responses | MCP server name |
| SessionEnd | When a session terminates | termination reason |

### Recommendation format

Include: hook event, matcher pattern, what the script checks, expected behavior (block vs warn).

## Skills

Repeatable workflows that should be encapsulated as skills (slash commands).

### When to recommend

- A multi-step workflow was performed that could be triggered with a single command
- The workflow was complex enough that recreating it would require significant context
- The workflow is likely to be reused (not a one-off investigation)
- The session revealed a pattern that would benefit from bundled reference files or scripts

### Recommendation format

Include: proposed name, description, estimated complexity (simple/moderate/complex), pattern
category (progressive-disclosure, script-bundled, action-router), key phases.

## Agents

Subagent configurations that improve quality. Verify supported fields (YAML frontmatter, tool
access, model selection, isolation modes) against the current subagent docs before recommending.

### When to recommend

- A task was done sequentially that could have been parallelized with subagents
- A specialized analysis would benefit from a dedicated agent with restricted scope
- A recurring delegation pattern emerged that should be formalized

### Recommendation format

Include: agent type, description, tool access, model recommendation, when to use.

## MCP Servers

Model Context Protocol servers that provide tool access to external systems.

### When to recommend

- The session needed access to a resource that wasn't available (database, API docs, dashboard)
- A manual lookup could have been automated with an MCP server
- An existing MCP server could have been used but wasn't

### Recommendation format

Include: server type (stdio/SSE/HTTP), resource provided, read-only vs read-write, expected
benefit.

## Settings / Configuration

Changes to Claude Code settings (settings.json, permissions, environment variables).

### When to recommend

- A permission was repeatedly denied that should be pre-approved
- An environment variable was needed but not configured
- A sandbox or security setting needs adjustment

### Recommendation format

Include: which settings file (user/project), the specific setting key, proposed value, rationale.

## Other Ecosystem Components

Additional component types may be relevant: output styles, plugins, LSP servers, status lines,
rules files. These evolve — research current capabilities when a session reveals a need that
doesn't fit the categories above.

## Priority Levels

| Priority | Definition | Action |
| --- | --- | --- |
| high | Prevents recurring errors, blocks bad patterns | Implement before next session |
| medium | Improves efficiency or quality | Queue for implementation |
| low | Nice to have, minor improvement | Note for future consideration |
