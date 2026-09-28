# Upstream source: Claude Code releases

What this marketplace decided about its own components in response to Claude Code releases, and
the problem each decision solves. Nothing here restates a changelog item: upstream owns that text at
`https://code.claude.com/docs/en/changelog.md`, and a copy only drifts. A release that produced no
decision leaves no row. The harness facts a skill restates stay in that skill under the
upstream-drift convention; a correction to one of them is recorded in the owning plugin's
CHANGELOG, and this file points at it rather than repeating it.

**Last audited upstream state:** changelog through `2.1.263` (published 2026-09-06), read as raw
markdown on 2026-09-08. Git history of this file records *when*; this line records only *what was
read*. `/claude-ops:changelog status` reads this line; the default range for `diff` and `apply`
runs from it to the newest published release.

**Recheck trigger:** a new release block appears above the version on the line above. Nothing before
`2.1.257` was read release by release; the fleet's coverage of older releases rests on each skill's
own verification stamps and the docs-conformance rechecks those stamps trigger.

Rows below are the decisions from that read. A record names the pull request that applied it, or
the branch that carries the apply when that branch has no pull request yet. Pages fetched again on
2026-09-28 for the rows in this file did not move the marker: later releases were not read as a range.

## Corrected

| Decision | Items | Owner surface | Record |
|---|---|---|---|
| Model ladder: `fable` resolves to Fable 5.1; gateway sessions still resolve to Fable 5 | 257-001, 257-090, 260-015 | `docs/plugin-philosophy.md`; playbooks boris | [#5059](https://github.com/melodic-software/claude-code-plugins/pull/5059) |
| On Fable 5.1, an effort change keeps the prompt cache | 260-049, 257-005 | `docs/plugin-philosophy.md` | [#5059](https://github.com/melodic-software/claude-code-plugins/pull/5059) |
| Opus 5 and Fable 5.1 have no first-run effort hold; `--effort` lifts a hold for that session | 257-083 | playbooks boris autonomy | [#5059](https://github.com/melodic-software/claude-code-plugins/pull/5059) |
| Bundled `claude-api`: prompt-audit steps held through the 2.1.282 read; model-migration gained an eval section and refreshed samples in 2.1.260 | 260-050 | audit-instructions criteria; `docs/specs/prompt-audit-skills-2026-09.md` | this file |
| 1M-context compact happens shortly before the limit | 260-047 | context-guard README | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Read/Edit deny covers redirect targets; the reverted 2.1.259 Bash-argument widening stays out | 257-052, 259-007, 260-040 | claude-config `required-permissions.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) and `cursor/4027-changelog-permissions-37e9` |
| Project `defaultMode: "bypassPermissions"` is ignored, like `"auto"` | 257-089 | audit-permission-state C2 | [#5059](https://github.com/melodic-software/claude-code-plugins/pull/5059) |
| Under `allowManagedPermissionRulesOnly`, `--allowedTools` is ignored and `--disallowedTools` plus session deny/ask survive reload | 257-034 | audit-permission-state criteria; `permission-merge.sh` | `cursor/4027-changelog-permissions-37e9` |
| Ask-rule quote is on the auto-mode config page; #42797 is closed; #83766 is open; compound and subshell paths prompt | 257-044 | audit-permission-state criteria | `cursor/4027-changelog-permissions-37e9` |
| `strictPluginOnlyCustomization` is `true` or a per-surface array; `"mcp"` blocks user and project MCP servers | 257-031 | `required-permissions.md`; hook-coverage reading | `cursor/4027-changelog-permissions-37e9` |
| Interactive `!` shell-mode runs outside the sandbox | 260-057, 257-029 | `required-permissions.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) and `cursor/4027-changelog-permissions-37e9` |
| Unparsable managed settings refuse startup; unparsable user settings pause the retention sweep | 259-023 | audit-permission-state; audit-performance | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) and `cursor/4027-changelog-permissions-37e9` |
| Server-managed settings cache at `~/.claude/remote-settings.json`; merge is `managedSourcesBehavior`, with `awsPairs` and `ripgrep` taken whole | 257-085, 261-001, 257-084 | `lib/managed-scope.sh`; audit-permission-state | `cursor/4027-changelog-permissions-37e9` |
| Only `deniedMcpServers` removes a managed connector | 259-035 | context-budget connectors lever | [#5059](https://github.com/melodic-software/claude-code-plugins/pull/5059) |
| `/reload-plugins` runs in `-p` and SDK sessions; an in-context loop is unprobed | 260-003 | lanes `refresh.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Worktree isolation is four named checks; the `$`-free precompute rule holds for git blocks | 257-054, 259-029 | worktree `gather-block.md`; skill-authoring precompute | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| `/context` counts with the token-counting API, or a local estimate from 2.1.261 | 261-041, 261-018 | context-budget | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) and `cursor/4027-changelog-adoptions-37e9` |
| CLI instruction surfaces include the append-system-prompt file flags | 261-003 | `docs/specs/agent-doc-surfaces.md` | [#5059](https://github.com/melodic-software/claude-code-plugins/pull/5059) |
| Permission rules may contain `)`; text after the close is `Malformed Tool(content) rule`; an unusable deny guards the literal path | 260-007, 260-008, 260-046, 260-052 | permission-plane lint C6; permission-rule-check | `cursor/4027-changelog-permissions-37e9` |
| Auto mode prompts once before a read outside the working directories; Read, Grep, Glob, and LSP can be fenced | 257-007 | `required-permissions.md` | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) and `cursor/4027-changelog-permissions-37e9` |

## Nominated

The store verdict is human-written. No row was written to `docs/native-surfaces/records.json`.

| Candidate | Items | Component | Record |
|---|---|---|---|
| Stale sandbox mask files | 257-006 | `audit-install-state`, routed through `audit-native-overlap` | nominated, pending human verdict, [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |

## Adopted

| Decision | Items | Component | Record |
|---|---|---|---|
| `--permission-prompts none` on lane launch, babysit, and autonomy dispatch | 259-002 | claude-ops lanes; source-control babysit; autonomy | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) and `cursor/4027-changelog-adoptions-37e9` |
| The same flag on the running-retro observer, keeping `dontAsk` | 259-002 | session-flow observer | `cursor/4027-changelog-adoptions-37e9` |
| The same flag on `hop_chain.py`, keeping `bypassPermissions` | 259-002 | session-flow harness | this file |
| `claude plugin validate --json` for per-file errors and warnings, gated on >= 2.1.259 | 259-004 | `scripts/validate-plugins.sh`; plugin-quality auditor | `cursor/4027-changelog-adoptions-37e9` |
| Skill frontmatter `model:` is turn-scoped and safe under auto mode | 259-015, 259-010 | skill-quality; skill-authoring; `docs/plugin-philosophy.md` | `cursor/4027-changelog-adoptions-37e9` |
| `/status` and `claude doctor` carry policy load, helper refresh, and which credential is in use | 257-074, 260-013, 260-012, 261-001 | audit-permission-state completeness note | `cursor/4027-changelog-adoptions-37e9` |
| The audit-pass `/doctor` handoff names those same three reads and does not invent a local substitute | 257-074, 260-013, 260-012 | audit-pass `doctor-handoff.md` | this file |
| `managedMcpServers` is attributed when present; no `claude mcp list` label is invented | 259-001 | mcp-tools audit-posture | `cursor/4027-changelog-adoptions-37e9` |
| `bashOutputMaxChars` is a documented lever and is not raised by default. `taskOutputMaxChars` was recorded removed in 2.1.277 | 261-002, 257-002 | claude-config audit checklist | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| Prompt-cache miss cause routes to `/usage` and `prompt_cache.last_miss_cause` | 260-002 | observability read-routing; context-guard reader | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) and `cursor/4027-changelog-adoptions-37e9` |

## Declined

| Capability | Items | Reason | Record |
|---|---|---|---|
| `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` in lanes | 257-004 | Overrides every agent-definition `model:` pin. Reopen when the env-vars page documents FORCE and the `inherit` interaction | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| `/advisor` text form as a headless lane default | 260-004 | No doc page states it. Reopen when a doc page states it, or a `-p` probe shows it applies | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |
| `claude --resume <id> --bg` for `lanes restart` | 257-087 | Absent from cli-reference. Reopen when cli-reference documents it, or a probe settles prompt and name handling | [#5156](https://github.com/melodic-software/claude-code-plugins/pull/5156) |

## Docs lag

The read also found upstream pages whose text contradicted the changelog. Those pages are not
component work. They stay input to `/claude-ops:known-issues`, and any correction above that cites
one of them cites the changelog as the newer statement.
