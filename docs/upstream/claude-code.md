# Upstream source: Claude Code releases

What this marketplace decided about its own components in response to Claude Code releases, and
the problem each decision solves. Nothing here restates a changelog item: upstream owns that text at
`https://code.claude.com/docs/en/changelog.md`, and a copy only drifts. A release that produced no
decision leaves no row. The harness facts a skill restates stay in that skill under the
upstream-drift convention; a correction to one of them is recorded in the owning plugin's
CHANGELOG, and this file points at it rather than repeating it.

**Last audited upstream state:** changelog through `2.1.296` (published 2026-10-09), read as raw
markdown on 2026-10-10. Git history of this file records *when*; this line records only *what was
read*. `/harness-ops:changelog status` reads this line; the default range for `diff` and `apply`
runs from it to the newest published release.

**Recheck trigger:** a new release block appears above the version on the line above. Nothing before
`2.1.257` was read release by release; the fleet's coverage of older releases rests on each skill's
own verification stamps and the docs-conformance rechecks those stamps trigger.

Rows below are the decisions from that read. A record names the pull request that first carried
the apply, or this file when the apply is on the branch that introduces the ledger. Pages fetched
again on 2026-09-28 for the rows in this file did not move the marker: later releases were not read
as a range.

Rows whose items fall in `2.1.265` through `2.1.296` come from a read of that range; every row is
applied in a merged pull request, nominated, declined, or deferred. A row whose decision starts
with "Deferred" names the issue that tracks it.

## Corrected

| Decision | Items | Owner surface | Record |
|---|---|---|---|
| Model ladder: `fable` resolves to Fable 5.1; gateway sessions still resolve to Fable 5 | 257-001, 257-090, 260-015 | `docs/plugin-philosophy.md`; playbooks boris | [#5154](https://github.com/melodic-software/claude-code-plugins/pull/5154) |
| On Fable 5.1, an effort change keeps the prompt cache | 260-049, 257-005 | `docs/plugin-philosophy.md` | [#5154](https://github.com/melodic-software/claude-code-plugins/pull/5154) |
| Opus 5.5 starts at `medium` unless an explicit choice (`CLAUDE_CODE_EFFORT_LEVEL`, `--effort`, `/effort`) or a saved level sets one; a top-level `effortLevel` in the user settings file does not count for Opus 5.5 and still applies on Opus 5, Fable 5.1 and earlier; `effortLevel` in project, local or managed settings or via `--settings` applies to every model | 257-083 | playbooks boris autonomy | [#5154](https://github.com/melodic-software/claude-code-plugins/pull/5154) |
| Bundled `claude-api`: prompt-audit steps held through the 2.1.282 read; model-migration gained an eval section and refreshed samples in 2.1.260 | 260-050 | audit-instructions criteria; ADR-0028 | this file |
| 1M-context compact happens shortly before the limit | 260-047 | context-guard README | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Read/Edit deny covers redirect targets; the reverted 2.1.259 Bash-argument widening stays out | 257-052, 259-007, 260-040 | harness-config `required-permissions.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Project `defaultMode: "bypassPermissions"` is ignored, like `"auto"` | 257-089 | audit-permission-state C2 | [#5154](https://github.com/melodic-software/claude-code-plugins/pull/5154) |
| Under `allowManagedPermissionRulesOnly`, `--allowedTools` is ignored and `--disallowedTools` plus session deny/ask survive reload | 257-034 | audit-permission-state criteria; `permission-merge.sh` | [#5159](https://github.com/melodic-software/claude-code-plugins/pull/5159) |
| Ask-rule quote is on the auto-mode config page; #42797 is closed; #83766 is open; compound and subshell paths prompt | 257-044 | audit-permission-state criteria | [#5159](https://github.com/melodic-software/claude-code-plugins/pull/5159) |
| `strictPluginOnlyCustomization` is `true` or a per-surface array; `"mcp"` blocks user and project MCP servers | 257-031 | `required-permissions.md`; hook-coverage reading | [#5159](https://github.com/melodic-software/claude-code-plugins/pull/5159) |
| Interactive `!` shell-mode runs outside the sandbox | 260-057, 257-029 | `required-permissions.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Unparsable managed settings refuse startup; unparsable user settings pause the retention sweep | 259-023 | audit-permission-state; audit-performance | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Server-managed settings cache at `~/.claude/remote-settings.json`; merge is `managedSourcesBehavior`, with `awsPairs` and `ripgrep` taken whole | 257-085, 261-001, 257-084 | `lib/managed-scope.sh`; audit-permission-state | [#5159](https://github.com/melodic-software/claude-code-plugins/pull/5159) |
| Only `deniedMcpServers` removes a managed connector | 259-035 | context-budget connectors lever | [#5154](https://github.com/melodic-software/claude-code-plugins/pull/5154) |
| `/reload-plugins` runs in `-p` and SDK sessions; an in-context loop is unprobed | 260-003 | lanes `refresh.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Worktree isolation is four named checks; the `$`-free precompute rule holds for git blocks | 257-054, 259-029 | worktree `gather-block.md`; skill-authoring precompute | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| `/context` counts with the token-counting API, or a local estimate from 2.1.261 | 261-041, 261-018 | context-budget | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| CLI instruction surfaces include the append-system-prompt file flags | 261-003 | `docs-hygiene:write-for-agents` | [#5154](https://github.com/melodic-software/claude-code-plugins/pull/5154) |
| Permission rules may contain `)`; text after the close is `Malformed Tool(content) rule`; an unusable deny guards the literal path | 260-007, 260-008, 260-046, 260-052 | permission-plane lint C6; permission-rule-check | [#5159](https://github.com/melodic-software/claude-code-plugins/pull/5159) |
| Auto mode prompts once before a read outside the working directories; Read, Grep, Glob, and LSP can be fenced | 257-007 | `required-permissions.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Task-tool steps branch on whether the task tools are present, with the skill's checklist file as the fallback | 268-016 | code-tidying batch-simplify | [#6751](https://github.com/melodic-software/claude-code-plugins/pull/6751) |
| Handoff and workflow branch on task-tool presence instead of mandating a live `TaskList` call | 268-016 | session-flow handoff, workflow | [#6752](https://github.com/melodic-software/claude-code-plugins/pull/6752) |
| The pull-request monitor finds and stops its watch by the task id it got when arming, not through `TaskList` | 268-016 | source-control pull-request `monitor.md` | [#6753](https://github.com/melodic-software/claude-code-plugins/pull/6753) |
| Monitor watches pass `timeout_ms` and re-arm on expiry; no watch is described as session-persistent | 271-015 | source-control pull-request, babysit-prs | [#6753](https://github.com/melodic-software/claude-code-plugins/pull/6753) |
| The `--bare` lever names every bucket bare mode drops, not only memory files | 286-012 | context-budget `levers.json` | [#6778](https://github.com/melodic-software/claude-code-plugins/pull/6778) |
| The auto-compact window has a per-model settings surface that outranks the top-level key | 288-014, 288-066 | context-guard `reader-contract.md` | [#6777](https://github.com/melodic-software/claude-code-plugins/pull/6777) |
| Nested CLAUDE.md and path-scoped rules load on Read, Write, or Edit in scope | 288-061 | docs-hygiene `agent-doc-surfaces.md` | [#6770](https://github.com/melodic-software/claude-code-plugins/pull/6770) |
| Path-scoped rules load on Read, Write, or Edit of a matching file | 288-061 | harness-memory audit `official-guidance.md` | [#6754](https://github.com/melodic-software/claude-code-plugins/pull/6754) |
| The rendered instruction index says surfaces load on Read, Write, or Edit | 288-061 | instruction-placement `render-index.sh`; root `AGENTS.md` | [#6780](https://github.com/melodic-software/claude-code-plugins/pull/6780), tracked in [#6199](https://github.com/melodic-software/claude-code-plugins/issues/6199) |
| The standards contract says rules fire on a matching Read, Write, or Edit | 288-061 | `docs/conventions/standards/README.md` and its synced copies | [#6775](https://github.com/melodic-software/claude-code-plugins/pull/6775) |
| The per-project wipe is `claude purge`; the old name is the pre-2.1.288 form | 288-012 | harness-memory stateless; harness-ops install-state, performance, and skill-visibility audits | [#6754](https://github.com/melodic-software/claude-code-plugins/pull/6754), [#6762](https://github.com/melodic-software/claude-code-plugins/pull/6762) |
| The nested AGENTS.md check adds the @-mention trigger; the Bash-read case stays open | 290-132 | harness-memory `nested-agents-check.sh` | [#6754](https://github.com/melodic-software/claude-code-plugins/pull/6754) |
| The plugin-eval sandbox preflight exempts macOS `~/.docker/bin` links; the refusal text is a pointer record | 293-033 | evals plugin-eval | [#6765](https://github.com/melodic-software/claude-code-plugins/pull/6765) |
| The validator's no-grant tool list mirrors the plugin-evals page | 277-019 | evals validate `validate-cases.py` | [#6765](https://github.com/melodic-software/claude-code-plugins/pull/6765) |
| `claude logs` and `attach` take a session name; the id form stays as the fallback for older CLIs | 290-008 | fleet reach | [#6767](https://github.com/melodic-software/claude-code-plugins/pull/6767) |
| The automation-gaps boundary leaves hook enumeration to the native `/hooks` menu and points at the hooks docs for what it shows | 286-018 | harness-config audit-automation-gaps | [#6858](https://github.com/melodic-software/claude-code-plugins/pull/6858) |
| The C6-colonStar lint message says a mid-pattern `:*` matches with a literal colon, not nothing; a 2.1.296 probe confirmed the lint's premise, so it fires on the same rules | 282-036 | harness-config audit-permission-state | [#6858](https://github.com/melodic-software/claude-code-plugins/pull/6858) |
| The sandbox escape-surface table scopes `excludedCommands` and the ignored settings to repository project and local entries under an admin-required sandbox | 282-014 | harness-config `required-permissions.md` | [#6858](https://github.com/melodic-software/claude-code-plugins/pull/6858) |
| OTEL enable, exporter, endpoint, and content keys move to user settings or the shell; structure-only keys stay committed | 273-009, 282-003, 282-015 | harness-ops observability operator setup | [#6762](https://github.com/melodic-software/claude-code-plugins/pull/6762) |
| A per-call Agent `effort` reaches a named agent, as a per-call `model` already did | 292-003 | multi-agent route | [#6763](https://github.com/melodic-software/claude-code-plugins/pull/6763) |
| The Agent-tool fallback passes the verifier's effort | 292-003 | knowledge docpage-digest | [#6771](https://github.com/melodic-software/claude-code-plugins/pull/6771) |
| The plan-reviewer pin rationale no longer says the Agent tool lacks a per-call effort | 292-003 | planning `plan-reviewer.md` | [#6772](https://github.com/melodic-software/claude-code-plugins/pull/6772) |
| A bare agent fan-out can set effort per call; it no longer has to move to a workflow for that lever | 292-003 | songwriting object-writing | [#6773](https://github.com/melodic-software/claude-code-plugins/pull/6773) |
| Effort tiers: the Agent tool sets effort per call, and the `haiku` alias's effort support depends on the provider | 292-003, 293-002 | `docs/plugin-philosophy.md` | [#6775](https://github.com/melodic-software/claude-code-plugins/pull/6775) |
| The auto-mode start default is not described as plan-scoped; its exceptions point at permission-modes | 284-017, 285-019, 285-020 | `docs/conventions/permission-rule-hygiene/README.md` | [#6775](https://github.com/melodic-software/claude-code-plugins/pull/6775) |
| C4 warns past the skill's own length floor instead of failing, and a length record points at both sources; the README states no limit | 295-020, 296-013 | mcp-tools audit C4; README | [#6779](https://github.com/melodic-software/claude-code-plugins/pull/6779) |
| Injected precompute commands need a matching `allowed-tools` entry; a shell fallback cannot rescue a permission abort | 271-013 | playbooks skill-authoring `precompute-context.md` | [#6764](https://github.com/melodic-software/claude-code-plugins/pull/6764) |
| The `/code-review` boundary follows the code-review page's effort text | 290-030 | review quality-gate code mode | [#6766](https://github.com/melodic-software/claude-code-plugins/pull/6766) |
| The artifact script-host list follows the artifacts page; the inline-everything policy is unchanged | 281-025 | visualization `decision-matrix.md` | [#6769](https://github.com/melodic-software/claude-code-plugins/pull/6769) |
| Deferred until a fetched page states the price relation: the observer default's cheapest-tier wording | 293-002 | session-flow `observer_analysis_model` | [#6759](https://github.com/melodic-software/claude-code-plugins/issues/6759) |

## Nominated

The store verdict is human-written. No row was written to `docs/native-surfaces/records.json`.

| Candidate | Items | Component | Record |
|---|---|---|---|
| Stale sandbox mask files: `/doctor` warns about the 0-byte placeholders a killed session leaves on Linux and WSL2; the mask path is undocumented, so `audit-install-state` grows no pattern for it and the store verdict decides whether the audit routes that check to doctor ([sandboxing, Troubleshooting](https://code.claude.com/docs/en/sandboxing)) | 257-006 | `audit-install-state`, routed through `audit-native-overlap` | nominated, pending human verdict, [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Native critical-path detection for recursive deletes: the guard is proposed to keep, re-rationalized as a hard deny in every permission mode, the outside-allowed-roots class, and CLIs older than 2.1.292 ([permission-modes](https://code.claude.com/docs/en/permission-modes)) | 283-065, 292-023 | guardrails `block-root-delete-target.sh` | nominated, pending human verdict, this file |
| Native `onFailure` blocking: the hook-failure audit is proposed to keep, its purpose scoped to rows without `"block"` and to the events the field does not affect ([hooks, Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails)) | 295-002 | harness-ops `hook-failure-audit.sh` | nominated, pending human verdict, this file |
| Agent-view supervisor restarts: the OS-owned lane schedule is proposed to keep, with the "Lane crash" cell re-rationalized for background sessions ([agent-view, The supervisor process](https://code.claude.com/docs/en/agent-view#the-supervisor-process)) | 290-032, 290-050, 290-051, 292-031, 292-032 | harness-ops lanes `restart-consumer.md` | nominated, pending human verdict, this file |

## Adopted

| Decision | Items | Component | Record |
|---|---|---|---|
| `--permission-prompts none` on lane launch, babysit, and autonomy dispatch; documented for print mode and unattended runs, denial under `--bg` not probed | 259-002 | harness-ops lanes; source-control babysit; autonomy | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| The same flag on the running-retro observer, keeping `dontAsk` | 259-002 | session-flow observer | [#5161](https://github.com/melodic-software/claude-code-plugins/pull/5161) |
| The same flag on `hop_chain.py`, keeping `bypassPermissions` | 259-002 | session-flow harness | [#5239](https://github.com/melodic-software/claude-code-plugins/pull/5239) |
| `claude plugin validate --json` for per-file errors and warnings, gated on >= 2.1.259 | 259-004 | `scripts/validate-plugins.sh`; plugin-quality auditor | [#5161](https://github.com/melodic-software/claude-code-plugins/pull/5161) |
| Skill frontmatter `model:` is turn-scoped and safe under auto mode | 259-015, 259-010 | skill-quality; skill-authoring; `docs/plugin-philosophy.md` | [#5161](https://github.com/melodic-software/claude-code-plugins/pull/5161) |
| `/status` and `claude doctor` carry policy load, helper refresh, and which credential is in use | 257-074, 260-013, 260-012, 261-001 | audit-permission-state completeness note; audit-pass doctor handoff | this file |
| `managedMcpServers` is attributed when present; no `claude mcp list` label is invented | 259-001 | mcp-tools audit-posture | [#5161](https://github.com/melodic-software/claude-code-plugins/pull/5161) |
| `bashOutputMaxChars` is a documented lever and is not raised by default. `taskOutputMaxChars` was recorded removed in 2.1.277 | 261-002, 257-002 | harness-config audit checklist | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Prompt-cache miss cause routes to `/usage` and `prompt_cache.last_miss_cause` | 260-002 | observability read-routing; context-guard reader | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| A `disable-web-fetch` lever; a 2.1.296 probe showed the variable removes WebFetch from the tool list, and its size depends on whether WebFetch is deferred | 285-002 | context-budget `levers.json` | [#6778](https://github.com/melodic-software/claude-code-plugins/pull/6778) |
| The WebFetch truncation hook matches the read-on note (captured by a 2.1.296 probe) and points at the note's offset, with `/discovery:read-docs` as the other route | 290-047 | discovery `webfetch-truncation.mjs` | [#6776](https://github.com/melodic-software/claude-code-plugins/pull/6776) |
| `omitClaudeMd: true` on the gated fetch and web-only stage agents | 271-006 | discovery docs-fetcher, sweep-worker; multi-agent docs-fetcher, drift-checker | [#6776](https://github.com/melodic-software/claude-code-plugins/pull/6776), [#6763](https://github.com/melodic-software/claude-code-plugins/pull/6763) |
| The role map's resolved effort applies to bare Agent dispatches | 292-003 | multi-agent route | [#6763](https://github.com/melodic-software/claude-code-plugins/pull/6763) |
| The scripted install uses `plugin install --marketplace`, keeping the two-step form for older CLIs | 292-002, 275-006 | dometrain setup | [#6768](https://github.com/melodic-software/claude-code-plugins/pull/6768) |
| The plugin-eval preflight reads `git --version` | 283-022 | evals plugin-eval | [#6765](https://github.com/melodic-software/claude-code-plugins/pull/6765) |
| Category H reads `deniedModels` and `availableModelsMatch` and warns when either sits outside managed settings | 283-003, 283-004 | harness-config audit | [#6858](https://github.com/melodic-software/claude-code-plugins/pull/6858) |
| The permission merge reports a `!` carve-out as its own record scoped to its settings file; a bare `!` is a known gap | 269-030 | harness-config audit-permission-state `permission-merge.sh` | [#6858](https://github.com/melodic-software/claude-code-plugins/pull/6858) |
| The observability setup sets `OTEL_METRICS_INCLUDE_REPOSITORY` so the repository columns fill | 269-005 | harness-ops observability | [#6762](https://github.com/melodic-software/claude-code-plugins/pull/6762) |
| A `run_in_background` wait passes an explicit `timeout` and re-arms on the stop notice | 285-014, 288-010 | implementation `implementer.md`; source-control pull-request `monitor.md` | [#6774](https://github.com/melodic-software/claude-code-plugins/pull/6774), [#6753](https://github.com/melodic-software/claude-code-plugins/pull/6753) |
| C19 recognizes a per-tool `anthropic/alwaysLoad: false`, and the audit grades against MCP specification 2026-07-28 | 285-013, 292-011 | mcp-tools audit | [#6779](https://github.com/melodic-software/claude-code-plugins/pull/6779) |
| The posture inventory marks `"type": "sdk"` entries as skipped by the client | 274-018 | mcp-tools audit-posture `inventory.sh` | [#6779](https://github.com/melodic-software/claude-code-plugins/pull/6779) |
| The validate report surfaces `gatingHooks` entries without a `.catch` | 290-006 | `scripts/validate-plugins.sh`; `scripts/plugin-validate-report.mjs` | [#6775](https://github.com/melodic-software/claude-code-plugins/pull/6775) |
| The local development loop loads a folder of plugins with one `--plugin-dir` | 265-003 | `docs/migration-playbook.md` | [#6775](https://github.com/melodic-software/claude-code-plugins/pull/6775) |
| Deferred, too large for one session: a Haiku 5.5 model-adaptation chapter | 293-002 | playbooks fable-5 | [#4348](https://github.com/melodic-software/claude-code-plugins/issues/4348) |
| Deferred until the older-client probe lands: which plugin hook rows take `onFailure: "block"`. A 2.1.296 probe showed a plugin `hooks.json` row honors it and `claude plugin validate` accepts it | 295-002 | `docs/conventions/hook-budget/README.md`; discovery, disk-hygiene, guardrails, and multi-agent blocking hooks | [#6755](https://github.com/melodic-software/claude-code-plugins/issues/6755) |
| Deferred until the env-vars page documents it: naming the overloaded-retry delay ceiling as a 529 mitigation | 296-005 | guardrails `workflow-resilience-check.sh` | [#6756](https://github.com/melodic-software/claude-code-plugins/issues/6756) |
| Deferred pending a capture of real `--json` results: replacing sync-run's text scraping | 268-007 | harness-ops plugins `sync-run.sh` | [#6757](https://github.com/melodic-software/claude-code-plugins/issues/6757) |
| Deferred pending probe: attributing subagent Write and Edit rule loads through InstructionsLoaded | 288-069 | instruction-placement `verified-mechanics.md` | [#6758](https://github.com/melodic-software/claude-code-plugins/issues/6758) |
| Deferred until the snapshot survey re-runs: closing the plugin `bin/` PATH gap on Windows | 284-040 | `docs/conventions/permission-rule-hygiene/README.md` | [#6760](https://github.com/melodic-software/claude-code-plugins/issues/6760) |
| Deferred until the settings file written and sensitive-option handling are confirmed: `claude plugin configure` as the headless reconfiguration route | 285-004 | `docs/conventions/plugin-reconfiguration/README.md` | [#6761](https://github.com/melodic-software/claude-code-plugins/issues/6761) |

## Declined

| Capability | Items | Reason | Record |
|---|---|---|---|
| `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` in lanes | 257-004 | Overrides every agent-definition `model:` pin. The reopen condition was met on 2026-09-29: the env-vars page documents FORCE (v2.1.257 or later), and the env-vars and sub-agents pages document the `inherit` interaction. The owner kept it declined on 2026-10-01 ([opus-5-5-task-cost.md](opus-5-5-task-cost.md)). Setting `CLAUDE_CODE_SUBAGENT_MODEL` alone does not move the built-in Plan or Explore subagents ([sub-agents: Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model)) | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| `/advisor` text form as a headless lane default | 260-004 | No doc page states it. Reopen when a doc page states it, or a `-p` probe shows it applies | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| `claude --resume <id> --bg` for `lanes restart` | 257-087 | Absent from cli-reference. Reopen when cli-reference documents it, or a probe settles prompt and name handling | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| `omitClaudeMd` on testing `green-runner` | 271-006 | The agent holds an ungated Bash shell, and the field also drops the user CLAUDE.md where operators keep shell safety rules; the context saving does not outweigh that. Reopen if the workflow gates its Bash the way the docs-fetchers are gated | this file |
| OSC 7501 or `$.ui.notify` in place of desktop-notification | 295-003, 295-013 | Neither is a routable native replacement for a permission or idle alert today; the plugin stays. Reopen when the mods reference lists `$.ui.notify` or terminal-config names a Windows notification path | [#6228](https://github.com/melodic-software/claude-code-plugins/issues/6228) |

No change for 280-030: a 2.1.296 probe showed PreToolUse and PostToolUse hooks receive a Write sent with alias keys as the normalized `file_path` and `content`, so guards keyed on `.tool_input.file_path` see those writes.

## Docs lag

The read also found upstream pages whose text contradicted the changelog. Those pages are not
component work. They stay input to `/harness-ops:known-issues`, and any correction above that cites
one of them cites the changelog as the newer statement.

The `2.1.265` through `2.1.296` read recorded the topics below. Each row names only the topic, the
release, and the page; the release notes and the page hold their own text. The last two rows are
not changelog-versus-page pairs: a disagreement between two docs pages, and a page missing from the
docs index.

| Topic | Items | Release | Page |
|---|---|---|---|
| Default length kept for MCP tool descriptions and server instructions | 296-013 | [2.1.296](https://code.claude.com/docs/en/changelog#2-1-296) | [mcp, Tool search for MCP server authors](https://code.claude.com/docs/en/mcp#tool-search-for-mcp-server-authors); [env-vars](https://code.claude.com/docs/en/env-vars) |
| Length kept for descriptions loaded through tool search | 295-020 | [2.1.295](https://code.claude.com/docs/en/changelog#2-1-295) | [mcp](https://code.claude.com/docs/en/mcp) |
| `onFailure` on plugin `hooks.json` rows and on older clients | 295-002 | [2.1.295](https://code.claude.com/docs/en/changelog#2-1-295) | [hooks, Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails) |
| `$.ui.notify` in the mods API | 295-013 | [2.1.295](https://code.claude.com/docs/en/changelog#2-1-295) | [mods reference, API methods](https://code.claude.com/docs/en/plugins/mods/reference#mods-api-methods) |
| Terminals that implement OSC 7501 | 295-003 | [2.1.295](https://code.claude.com/docs/en/changelog#2-1-295) | [terminal-config, See session status in your terminal](https://code.claude.com/docs/en/terminal-config#see-session-status-in-your-terminal) |
| `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` | 296-004 | [2.1.296](https://code.claude.com/docs/en/changelog#2-1-296) | [env-vars](https://code.claude.com/docs/en/env-vars); [workflows](https://code.claude.com/docs/en/workflows) |
| `CLAUDE_CODE_OVERLOADED_RETRY_MAX_DELAY_MS` | 296-005 | [2.1.296](https://code.claude.com/docs/en/changelog#2-1-296) | [env-vars](https://code.claude.com/docs/en/env-vars) |
| `autoCompactWindow` in subagent frontmatter and `--agents` | 296-003 | [2.1.296](https://code.claude.com/docs/en/changelog#2-1-296) | [sub-agents](https://code.claude.com/docs/en/sub-agents) |
| WebFetch read-on notice and `offset` input | 290-047 | [2.1.290](https://code.claude.com/docs/en/changelog#2-1-290) | [tools-reference, WebFetch tool behavior](https://code.claude.com/docs/en/tools-reference#webfetch-tool-behavior) |
| What attaches a subdirectory AGENTS.md | 290-132 | [2.1.290](https://code.claude.com/docs/en/changelog#2-1-290) | [memory, AGENTS.md](https://code.claude.com/docs/en/memory#agents-md) |
| `/code-review` effort coverage per model | 290-030 | [2.1.290](https://code.claude.com/docs/en/changelog#2-1-290) | [code-review](https://code.claude.com/docs/en/code-review) |
| A pending `/loop` wakeup across a supervisor restart | 292-032 | [2.1.292](https://code.claude.com/docs/en/changelog#2-1-292) | [agent-view, The supervisor process](https://code.claude.com/docs/en/agent-view#the-supervisor-process) |
| Monitor `persistent` and `timeout_ms` | 271-015 | [2.1.271](https://code.claude.com/docs/en/changelog#2-1-271) | [tools-reference, Monitor tool](https://code.claude.com/docs/en/tools-reference#monitor-tool) |
| TaskOutput tool status | 277-019 | [2.1.277](https://code.claude.com/docs/en/changelog#2-1-277) | [tools-reference](https://code.claude.com/docs/en/tools-reference) |
| Mid-pattern `:*` Bash rules loaded from settings files | 282-036 | [2.1.282](https://code.claude.com/docs/en/changelog#2-1-282) | [permissions, Wildcard patterns](https://code.claude.com/docs/en/permissions#wildcard-patterns) |
| What `--bare` and `CLAUDE_CODE_SIMPLE` skip | 286-012 | [2.1.286](https://code.claude.com/docs/en/changelog#2-1-286) | [cli-reference](https://code.claude.com/docs/en/cli-reference); [env-vars](https://code.claude.com/docs/en/env-vars) |
| Release that made auto the start default | 284-017 | [2.1.284](https://code.claude.com/docs/en/changelog#2-1-284) | [permission-modes, Which mode a session starts in](https://code.claude.com/docs/en/permission-modes#which-mode-a-session-starts-in) |
| Repository settings ignored under an admin-required sandbox | 282-014 | [2.1.282](https://code.claude.com/docs/en/changelog#2-1-282) | [sandboxing, Repository settings under an admin-required sandbox](https://code.claude.com/docs/en/sandboxing#repository-settings-under-an-admin-required-sandbox) |
| A bare `!` permission rule | 269-030 | [2.1.269](https://code.claude.com/docs/en/changelog#2-1-269) | [permissions, Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit) |
| What `CLAUDE_CODE_DISABLE_WEB_FETCH` does to the tool definition | 285-002 | [2.1.285](https://code.claude.com/docs/en/changelog#2-1-285) | [env-vars](https://code.claude.com/docs/en/env-vars) |
| The file `claude plugin configure` writes and its sensitive-option handling | 285-004 | [2.1.285](https://code.claude.com/docs/en/changelog#2-1-285) | [plugins CLI reference, plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure) |
| `--json` result fields for plugin install and update | 268-007 | [2.1.268](https://code.claude.com/docs/en/changelog#2-1-268) | [plugins CLI reference, plugin JSON result](https://code.claude.com/docs/en/plugins/cli-reference#plugin-json-result) |
| Plugins added or removed under a `--plugin-dir` folder while running | 265-003 | [2.1.265](https://code.claude.com/docs/en/changelog#2-1-265) | [plugins CLI reference, Flags that load a plugin for one session](https://code.claude.com/docs/en/plugins/cli-reference#flags-that-load-a-plugin-for-one-session) |
| The old `claude project purge` name | 288-012 | [2.1.288](https://code.claude.com/docs/en/changelog#2-1-288) | [claude-directory, Clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data) |
| `tool_decision` for unanswered asks, and `blocked_on_user` | 288-039, 288-040 | [2.1.288](https://code.claude.com/docs/en/changelog#2-1-288) | [monitoring-usage, Tool decision event](https://code.claude.com/docs/en/monitoring-usage#tool-decision-event) |
| InstructionsLoaded input fields for subagent-triggered loads | 288-069 | [2.1.288](https://code.claude.com/docs/en/changelog#2-1-288) | [hooks, InstructionsLoaded input](https://code.claude.com/docs/en/hooks#instructionsloaded-input) |
| One agent id across plugin hook events | 289-002 | [2.1.289](https://code.claude.com/docs/en/changelog#2-1-289) | [mods reference](https://code.claude.com/docs/en/plugins/mods/reference) |
| The plugin-eval credential-store refusal | 293-033 | [2.1.293](https://code.claude.com/docs/en/changelog#2-1-293) | [plugin-evals](https://code.claude.com/docs/en/plugin-evals) |
| Agent hooks on PermissionRequest | 280-023 | [2.1.280](https://code.claude.com/docs/en/changelog#2-1-280) | [hooks, Prompt-based hooks](https://code.claude.com/docs/en/hooks#prompt-based-hooks) |
| Write tool alias input keys | 280-030 | [2.1.280](https://code.claude.com/docs/en/changelog#2-1-280) | [hooks, PreToolUse input](https://code.claude.com/docs/en/hooks#pretooluse-input) |
| Sources whose `type: "sdk"` MCP entries are skipped | 274-018 | [2.1.274](https://code.claude.com/docs/en/changelog#2-1-274) | [mcp](https://code.claude.com/docs/en/mcp) |
| MCP server instructions in `/context` | 283-048 | [2.1.283](https://code.claude.com/docs/en/changelog#2-1-283) | [costs](https://code.claude.com/docs/en/costs) |
| The pinned-effort exception | 267-020 | [2.1.267](https://code.claude.com/docs/en/changelog#2-1-267) | [model-config, Set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level) |
| Version floor of the task-tool default set and `CLAUDE_CODE_ENABLE_TODO_TOOLS` | 268-016 | [2.1.268](https://code.claude.com/docs/en/changelog#2-1-268) | [env-vars](https://code.claude.com/docs/en/env-vars); [tools-reference, Task tool availability](https://code.claude.com/docs/en/tools-reference#task-tool-availability) |
| The auto-mode classifier billing page in the docs index | 278-001 | [2.1.278](https://code.claude.com/docs/en/changelog#2-1-278) | [auto-mode-classifier-billing](https://code.claude.com/docs/en/auto-mode-classifier-billing) |
