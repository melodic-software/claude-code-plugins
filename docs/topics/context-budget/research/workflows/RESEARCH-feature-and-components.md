---
topic: claude-code-workflows-context-cost-and-disable
section: feature-and-components
abstract: Dynamic workflows are Claude-authored JS orchestration scripts; they add a Workflow tool, /workflows and /deep-research commands, an ultracode keyword and effort level, two save directories, a plugin workflows/ component, and five config keys.
claims:
  - claim: "The workflows feature is 'dynamic workflows': a JavaScript script that orchestrates subagents at scale, written by Claude and executed by a runtime in the background; it requires Claude Code v2.1.154 or later."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "Anthropic (GitHub upstream repo)"
      - url: "local: node_modules/@anthropic-ai/claude-code/bin/claude.exe v2.1.232, WorkflowTool module"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
  - claim: "A session with workflows enabled gains a built-in `Workflow` tool that is listed in the tools reference with 'Permission required: Yes'."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/tools-reference"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "local: claude.exe, `userFacingName(){return\"Workflow\"}` and `isEnabled:()=>jD()`"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://code.claude.com/docs/en/agent-sdk/typescript"
        tier: 1
        pool: "Anthropic (Agent SDK reference, referenced from the workflows page)"
  - claim: "Workflows also add the `/workflows` progress-view command and the bundled `/deep-research` workflow command."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/commands"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "Anthropic (GitHub upstream repo)"
  - claim: "Plugins distribute workflows through a `workflows/` directory at the plugin root, overridable by the `workflows` manifest component-path field."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
produced_by: phase-1-and-2
---

# What the workflows feature is, and what it adds to a session

All URLs fetched **2026-08-17**. Tier 0 evidence is from the locally installed
`@anthropic-ai/claude-code` **v2.1.232** binary; latest upstream at time of research is **2.1.233**.

## The feature

> "A dynamic workflow is a JavaScript script that orchestrates [subagents](/docs/en/sub-agents) at
> scale. Claude writes the script for the task you describe, and a runtime executes it in the
> background while your session stays responsive."
> — <https://code.claude.com/docs/en/workflows> (fetched 2026-08-17)

Availability note from the same page, verbatim:

> "Dynamic workflows require Claude Code v2.1.154 or later and are available on all paid plans, with
> Anthropic API access, and on Amazon Bedrock, Google Cloud's Agent Platform, and Microsoft Foundry.
> On Pro, turn them on from the Dynamic workflows row in `/config`."

The distinguishing property versus subagents/skills/agent teams is that the plan lives in code:
intermediate results stay in script variables rather than in Claude's context window, so only the
final answer lands in context.

## Components the feature adds to a session

This is the inventory a context-trimming skill should care about. Each row names the surface and the
source that documents it.

| # | Component | Exact spelling / location | Source (fetched 2026-08-17) |
|---|---|---|---|
| 1 | **The `Workflow` tool** | tool name `Workflow`; "Permission required: **Yes**" | [tools-reference](https://code.claude.com/docs/en/tools-reference) |
| 2 | **`/workflows` command** | opens the run progress view (watch, pause, resume, save) | [commands](https://code.claude.com/docs/en/commands) |
| 3 | **`/deep-research` bundled workflow** | the one built-in workflow command; "runs only when you invoke it" | [workflows](https://code.claude.com/docs/en/workflows), [commands](https://code.claude.com/docs/en/commands) |
| 4 | **`ultracode` prompt keyword** | typed in a human prompt; highlighted in the input | [workflows](https://code.claude.com/docs/en/workflows) |
| 5 | **`ultracode` effort level** | `/effort ultracode`, `claude --effort ultracode`; v2.1.203+ | [workflows](https://code.claude.com/docs/en/workflows), [commands](https://code.claude.com/docs/en/commands) |
| 6 | **Project workflow directory** | `.claude/workflows/` (nearest one wins in a monorepo, v2.1.178+) | [workflows](https://code.claude.com/docs/en/workflows) |
| 7 | **Personal workflow directory** | `~/.claude/workflows/`, or `workflows/` under `CLAUDE_CONFIG_DIR` | [workflows](https://code.claude.com/docs/en/workflows) |
| 8 | **Plugin component directory** | `workflows/` at the plugin root; namespaced `/<plugin>:<name>` | [plugins-reference](https://code.claude.com/docs/en/plugins-reference) |
| 9 | **Plugin manifest field** | `"workflows"`, `string\|array`, *replaces* the default `workflows/` | [plugins-reference](https://code.claude.com/docs/en/plugins-reference) |
| 10 | **Settings keys** | `disableWorkflows`, `workflowKeywordTriggerEnabled`, `workflowSizeGuideline` (+ undocumented `enableWorkflows`, see the disable sidecar) | [settings](https://code.claude.com/docs/en/settings) |
| 11 | **Environment variables** | `CLAUDE_CODE_DISABLE_WORKFLOWS`, `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS` | [env-vars](https://code.claude.com/docs/en/env-vars) |
| 12 | **`/config` rows** | "Dynamic workflows", "Ultracode keyword trigger", "Dynamic workflow size" | [workflows](https://code.claude.com/docs/en/workflows) |
| 13 | **Task-panel progress line** | one-line progress summary below the input box; `Large workflow` warning | [workflows](https://code.claude.com/docs/en/workflows) |
| 14 | **Per-run script file** | written under the session directory in `~/.claude/projects/` | [workflows](https://code.claude.com/docs/en/workflows) |

Rows 1 and 3 are the only ones that consume model-visible context at startup; rows 2, 4–7 and 12–14
are UI/filesystem surfaces. Row 8/9 matter to a plugin maintainer packaging workflows, not to the
startup payload. **Which of these actually costs prefix tokens is the subject of the
`tool-loading-and-context-cost` sidecar** — do not infer the cost from this inventory alone.

## The plugin-directory detail, verbatim

The plugin structure listing puts `workflows/` at the plugin root alongside `commands/`, `agents/`,
and `skills/`:

> "The `.claude-plugin/` directory contains the `plugin.json` file. All other directories
> (commands/, agents/, skills/, workflows/, output-styles/, themes/, monitors/, hooks/) must be at
> the plugin root, not inside `.claude-plugin/`."
> — [plugins-reference](https://code.claude.com/docs/en/plugins-reference) (fetched 2026-08-17)

And the manifest field **replaces rather than extends** the default directory:

> "**Replaces the default**: `commands`, `agents`, `workflows`, `outputStyles`,
> `experimental.themes`, `experimental.monitors`. For example, when the manifest specifies
> `commands`, the default `commands/` directory is not scanned. To keep the default and add more,
> list it explicitly."
> — [plugins-reference](https://code.claude.com/docs/en/plugins-reference) (fetched 2026-08-17)
