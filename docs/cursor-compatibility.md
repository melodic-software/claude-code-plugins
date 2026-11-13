# Cursor compatibility

Cursor can load a Claude Code plugin and run its `hooks/hooks.json` hooks on the events it maps
(#7556 probe, with a test plugin). This note lists the hook events and matchers our plugins use that Cursor does not map. Each
one is an accepted no-op in Cursor: the hook does not run there, and nothing changes in Claude Code.
It also lists the tool restrictions Cursor does not enforce (see [Tool restrictions](#tool-restrictions)).
The marketplace ships no Cursor-specific files and no per-plugin Cursor edits.

Sources:

- **Cursor docs:** [Third-party hooks](https://cursor.com/docs/reference/third-party-hooks), read
  2026-11-02. The `.md` form of that URL returned 404 on that date.
- **Cursor skills and subagents docs:** [Skills](https://cursor.com/docs/skills) and
  [Subagents](https://cursor.com/docs/subagents), read 2026-11-03. The `.md` form of each URL
  returned 404 on that date.
- **#7556 probe:** the [probe result](https://github.com/melodic-software/claude-code-plugins/issues/7556#issuecomment-6586532476)
  on #7556: 8 headless runs of `cursor-agent` 2026.10.19-6bbf2c4 on Linux (WSL), 2026-11-02.

The per-plugin lists come from `plugins/*/hooks/hooks.json`. No hook in these lists was tested
one by one in Cursor, so each no-op below is predicted from the Cursor docs.

The event and matcher tables are a snapshot of those files at commit `208b23ae`, taken
2026-11-02. No check keeps them in sync, so a hook added or moved since then may be missing:
re-derive them from `plugins/*/hooks/hooks.json` before relying on them.

## What runs

The Cursor docs map these Claude Code events: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`,
`Stop`, `SubagentStop`, `SessionStart`, `SessionEnd` and `PreCompact`. They map these tools: `Bash`
to `Shell`, `Edit` and `Write` to `Write`, and `Read`, `Grep`, `Task`, `WebFetch` and `WebSearch`
to the same names. (Cursor docs)

In the #7556 probe, `SessionStart` fired in every run and `PreToolUse` with the `Bash` matcher
fired once per shell call. The `SessionStart` hook process received `CLAUDE_PLUGIN_ROOT` set to
the plugin directory. (#7556 probe)

## `UserPromptSubmit`

The Cursor docs list `UserPromptSubmit` as supported. (Cursor docs) It did not fire in any of the
8 headless Cursor CLI runs. (#7556 probe) The probe ran only the headless CLI, so its behavior in
the Cursor IDE is unverified. No plugin here registers `UserPromptSubmit` today. No manual check
is planned, per the [decision on #12484](https://github.com/melodic-software/claude-code-plugins/issues/12484#issuecomment-6588071825).

## Events Cursor does not map

Each hook on these events is an accepted no-op in Cursor.

| Event | Plugins | Basis |
|---|---|---|
| `PostToolBatch` | bash-format, biome-format, eol-normalizer, go-format, markdown-format, ruff-format | Not in the Cursor docs' event table |
| `Notification` | desktop-notification | Marked not supported in the Cursor docs |
| `PostCompact` | context-usage | Not in the Cursor docs' event table |
| `StopFailure` | harness-ops, rate-limits | Not in the Cursor docs' event table |
| `UserPromptExpansion` | disk-hygiene, harness-ops | Not in the Cursor docs' event table |
| `ConfigChange`, `InstructionsLoaded`, `PermissionDenied`, `PostToolUseFailure` | harness-ops | Not in the Cursor docs' event table |
| `WorktreeCreate`, `WorktreeRemove` | source-control | Not in the Cursor docs' event table |

The six formatters do not rewrite files in Cursor. They stay on `PostToolBatch`, since moving
them to `PostToolUse` would make them run after every edit in Claude Code. Cursor maps `Stop`, so
the opt-in end-of-turn check that bash-format, biome-format, go-format, markdown-format and
ruff-format register on `Stop` is expected to run. (Cursor docs)

## Tool matchers Cursor does not map

A hook whose matcher names only these tools does not run in Cursor. Where a matcher lists them
next to a mapped tool, such as `Write|Edit|NotebookEdit` or `Bash|PowerShell`, only the unmapped
alternatives are no-ops. The Cursor docs' tool table lists none of these names. (Cursor docs) The
page says nothing about MCP tool names either, so whether an `mcp__*` matcher fires in Cursor is
unknown, and is accepted either way.

| Matcher | Plugins |
|---|---|
| `NotebookEdit` | context-budget, guardrails |
| `PowerShell` | disk-hygiene, guardrails |
| `Skill` | disk-hygiene, harness-ops |
| `Workflow` | guardrails |
| `Artifact` | review |
| `mcp__*` names | guardrails, source-control |

The Cursor docs also mark `Glob` as not supported. (Cursor docs) No plugin hook matches it.

## `SessionStart` source matchers

disk-hygiene and harness-ops register `SessionStart` hooks with the source matcher
`startup|resume|clear|fork`. The Cursor docs do not cover `SessionStart` source matchers (Cursor
docs), and the #7556 probe did not test them, so whether these hooks run in Cursor is unknown.

## Tool restrictions

Only Claude Code acts on these frontmatter keys. Treat each as having no effect in Cursor:

| Key | Where | What it does in Claude Code | Cursor basis |
|---|---|---|---|
| `disallowed-tools` | Skill | Removes tools while the skill is active | Ignored in the #7556 probe |
| `disallowedTools` | Plugin agent | Removes tools from the agent | Ignored in the #7556 probe |
| `tools` | Plugin agent | Limits the agent to the listed tools | Not a field in the Cursor subagents docs; not probed |
| `allowed-tools` | Skill | Pre-approves tools for the invoking turn; limits nothing | Not a field in the Cursor skills docs; not probed |

In the #7556 probe, a skill with `disallowed-tools: Bash` ran a shell command, as did the control
skill without the key, and a plugin agent with `disallowedTools: "Bash"` also ran one. A
`PreToolUse` hook recorded each call. (#7556 probe) The Cursor skills docs list no tool field. The
Cursor subagents docs list `name`, `description`, `model`, `readonly` and `is_background`, and say
subagents inherit all tools from the parent. Those docs do not mention plugin agents. (Cursor
skills and subagents docs) The Claude Code skills docs say `allowed-tools` "does not restrict
which tools are available". ([Claude Code skills docs](https://code.claude.com/docs/en/skills),
read 2026-11-03)

So in Cursor, a skill or agent that `disallowed-tools`, `disallowedTools` or `tools` limits is
expected to keep every tool. An agent whose `tools` list leaves out every write tool is read-only
by its instructions only. A skill's `allowed-tools` grants no pre-approval in Cursor, so its tool
calls may prompt. These keys scope agent behavior and guard no secret, token, account or bill. A
plan that sets `disallowed-tools` in a skill per job holds in Claude Code only.

No plugin sets Cursor's `readonly` subagent field: the marketplace keeps one plugin source. A
`PreToolUse` hook that enforces an agent's own tool limits could back them in Cursor. It is added
only after a probe shows that Cursor blocks a call such a hook denies. If it is added, it covers
the read-only reviewer agents (reviewer agents whose `tools` list has no `Write`, `Edit` or
`NotebookEdit`), plus discovery's `researcher` and
`intent-tracer`, whose `disallowedTools` lists it would enforce. It does not cover every agent
with a `tools` list. The [decision on #12483](https://github.com/melodic-software/claude-code-plugins/issues/12483#issuecomment-6603179200)
records these choices.

To find the skills and agents that use these keys, search `plugins/*/skills/*/SKILL.md` and
`plugins/*/agents/*.md` for them.
