---
topic: tool-definitions-prefix-pruning
section: tool-inventory
abstract: "The tools-reference page lists 45 built-in tools but never marks any as prefix-loaded vs deferred; the split is observable only per-session, and the doc list is not exhaustive of tools actually present."
claims:
  - claim: "code.claude.com/docs/en/tools-reference enumerates 45 built-in tool names in its main table."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/tools-reference"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/tools-reference.md"
        tier: 0
        pool: "Anthropic / code.claude.com (raw markdown, parsed locally)"
  - claim: "The tools-reference page does NOT label which built-in tools are loaded in the prefix versus deferred behind ToolSearch. Only two rows touch deferral at all: ToolSearch and WaitForMcpServers."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/tools-reference"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
  - claim: "Anthropic documents the prefix-loaded built-in set only by open-ended example — 'core built-in tools such as Bash, Read, and Edit' — never as a closed list."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
  - claim: "A session can carry built-in tools that the tools-reference table does not list at all (observed: ListPlugins, ListSkills, SearchPlugins, SearchSkills)."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "session tool surface, Claude Code 2.1.232, captured 2026-08-17"
        tier: 0
        pool: "direct tool output (this session)"
produced_by: phase-1-2
---

# Built-in tool inventory, and the prefix/deferred split

## What the official inventory actually is

`https://code.claude.com/docs/en/tools-reference` (fetched 2026-08-17, page `lastmod`
`2026-08-16T14:28:29.785Z`) carries one table of built-in tools with a `Permission required` column.
Parsed from the raw markdown (`tools-reference.md`), it holds **45 tool names**:

`Agent`, `Artifact`, `AskUserQuestion`, `Bash`, `CronCreate`, `CronDelete`, `CronList`, `Edit`,
`EndConversation`, `EnterPlanMode`, `EnterWorktree`, `ExitPlanMode`, `ExitWorktree`, `Glob`, `Grep`,
`ListAgents`, `ListMcpResourcesTool`, `LSP`, `Monitor`, `NotebookEdit`, `PowerShell`,
`PushNotification`, `Read`, `ReadMcpResourceTool`, `RemoteTrigger`, `ReportFindings`,
`ScheduleWakeup`, `SendMessage`, `SendUserFile`, `ShareOnboardingGuide`, `Skill`, `TaskCreate`,
`TaskGet`, `TaskList`, `TaskOutput`, `TaskStop`, `TaskUpdate`, `TodoWrite`, `ToolSearch`,
`WaitForMcpServers`, `WebFetch`, `WebSearch`, `Workflow`, `Write`.

## The page does not answer the prefix-vs-deferred question

**This is the single most important negative finding for the skill.** The table has no column, and
the page has no section, marking a tool as prefix-loaded or deferred. Searching the full page for
`defer`, `tool search`, `upfront`, `withheld`, and `alwaysLoad` returns exactly two rows:

- `ToolSearch` — "Searches for and loads deferred tools when [tool search] is enabled"
- `WaitForMcpServers` — "Only appears when [tool search] is disabled, since `ToolSearch` handles the
  wait when it's enabled"

So the tools-reference page tells you a deferral system exists and which tool drives it, and nothing
about which tools it applies to.

## What Anthropic does say about the prefix-loaded built-ins

The only first-party statement is on the tool-search page
(`https://code.claude.com/docs/en/agent-sdk/tool-search`, fetched 2026-08-17):

> The SDK always loads core built-in tools such as Bash, Read, and Edit upfront and doesn't count
> them toward the threshold.

`such as` is an example, not an enumeration. **There is no published closed list of the
prefix-loaded built-in set.** A skill that needs the split must observe it per session rather than
hard-code it — see the falsification note below.

## Two documented, closed lists that DO exist (different questions)

Both are on `https://code.claude.com/docs/en/sub-agents` (fetched 2026-08-17) and neither is the
prefix/deferred split, but a skill inventorying startup context will meet them:

1. **The background-subagent built-in filter** — a closed list of what a *background* subagent keeps:
   `Read`, `Grep`, `Glob`, `Bash`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`,
   `WebSearch`, `TodoWrite`, `Skill`, `ToolSearch`, `EnterWorktree`, `ExitWorktree`, `Monitor`,
   `TaskStop`, `SendMessage`, `Artifact`. "Claude Code removes every other built-in tool from a
   background subagent, whether inherited or listed in the `tools` field."
2. **Agent-team teammates additionally keep** `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`,
   `CronCreate`, `CronDelete`, `CronList`.

## Model-conditional availability — a real prefix-size lever

`https://code.claude.com/docs/en/tools-reference#task-tool-availability` (fetched 2026-08-17):

> In Claude Code v2.1.233 and later, the following tools aren't available on Opus 4.8, Sonnet 5,
> Fable 5, Mythos 5, or later versions of those families unless you opt in: `TodoWrite`,
> `TaskCreate`, `TaskGet`, `TaskUpdate`, and `TaskList`. Those models keep track of multi-step work
> without a written checklist, and **the tools' definitions and reminders take up context, so Claude
> Code leaves them out.**

This is Anthropic doing exactly what the skill proposes — dropping definitions to save prefix — and
it is model-dependent, so a baseline captured on one model does not transfer to another.

## Tier-0 observation from this session (illustrative, not a general rule)

Claude Code **2.1.232**, model `claude-sonnet-5`, captured 2026-08-17. The session's own surface
splits as:

- **In the prefix** (full schemas present): `Artifact`, `Bash`, `Edit`, `Glob`, `Grep`, `Read`,
  `Skill`, `ToolSearch`, `Write`, plus **every** `mcp__Claude_Code_Remote__*` tool.
- **Deferred** (name-only, per the deferred-tool system reminder): `EnterWorktree`, `ExitWorktree`,
  `ListPlugins`, `ListSkills`, `Monitor`, `NotebookEdit`, `SearchPlugins`, `SearchSkills`,
  `SendMessage`, `TaskStop`, `WebFetch`, `WebSearch`, plus 65 `mcp__github__*` tools.

Two things worth carrying into the skill's design:

- **`ListPlugins`, `ListSkills`, `SearchPlugins`, `SearchSkills` appear in a live session but are
  absent from the tools-reference table.** The published inventory is therefore not exhaustive of
  what a real session carries, so a skill that inventories by diffing against the doc list will
  under-count.
- **Two MCP servers in one session landed on opposite sides of the split** — `Claude_Code_Remote`
  fully prefix-loaded, `github` fully deferred. That is the shape `alwaysLoad` produces (see
  `RESEARCH-deferral-controls.md`), but this run did not read the two servers' configuration, so the
  cause is **unverified** here.

## Practical consequence for the skill

The prefix/deferred split is **session state, not a documented constant**. The supported way to read
it is the deferred-tool system reminder plus `/context` (see `RESEARCH-measurement.md`), which
reports `System tools` and `System tools (deferred)` as separate buckets. Do not ship a hard-coded
table of which built-ins are deferred; it is model-, version-, surface-, and config-dependent.
