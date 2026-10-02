# Sources: the cited index for Claude Code mods

## Start here

Asked "what about mods?", do this in order:

1. Read [ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md). It holds the
   verdict (Defer), the three conditions that gate guard conversion, and the five go criteria.
2. Run [go-no-go.md](go-no-go.md). Criteria 1 to 3 are the quick check for a Claude Code pin bump;
   the full run is on demand. Any one criterion failing is no-go.
3. Consult this index for every link the verdict and the runbook rest on, and re-fetch what the
   runbook tells you to re-fetch.
4. The frozen report is in [research-2026-09-19/](research-2026-09-19/). Treat it as dated evidence,
   never as current state: the feature changed within 24 hours of the research run.
5. Standing rule for every check: `claude plugin --help` and a documentation grep return **false
   negatives**. Probe behavior, not help text.

## How to read the table

Each row is a pointer: the link, the topic we used it for (in our words; the source's own text is
read at the link, never stored here), the date it was last read, and what in this repository
relies on it. Everything below was fetched or re-fetched on **2026-09-19**, at Claude Code
**2.1.278**, with `anthropics/claude-code` `mods/` at **`92ec78f2`**. Where a row's date differs,
the row says so. Counts and hit totals are our own probe results. "Used by" names the ADR, the
runbook, or the report sidecar under `research-2026-09-19/` that relies on the source. Trust tiers
run first-party first; a claim's own basis label (`OBSERVED`, `SOURCE`, `BINARY`, `STAFF`,
`COMMUNITY`, `INFERRED`) is carried in the report, not here. Recheck trigger for every row: a
[go-no-go.md](go-no-go.md) run re-fetches it, and the row's date is refreshed with the outcome.

## First-party source tree and binary

| Link | What we used it for | As of | Used by |
|---|---|---|---|
| <https://github.com/anthropics/claude-code/tree/main/mods> | The published source of the four shipped mods, `types/`, `tsconfig.json`. The surface link for the gate-run row. | 2026-09-19 | ADR 0035, `plugin-philosophy.md`, `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/blob/main/mods/README.md> | What a mod is, the four mods and their seating, the testing kit, noun contracts, and the early-access stability statement criterion 5 checks for. | 2026-09-19 | ADR 0035 (criterion 5), go-no-go.md, `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/blob/92ec78f2/mods/README.md> | The same file pinned at the research commit, so a later diff is exact. | 2026-09-19 | go-no-go.md |
| <https://raw.githubusercontent.com/anthropics/claude-code/main/mods/README.md> | Raw form, for the greppable criterion-5 check. | 2026-09-19 | go-no-go.md |
| <https://raw.githubusercontent.com/anthropics/claude-code/92ec78f2/mods/README.md> | Raw form pinned at the research commit. | 2026-09-19 | `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts> | The declarations: the event and noun catalog, the tiers, `HookBudget`, `Registration.catch`. Our count: 12,990 lines; its first line names Claude Code 2.1.277 as the writer. | 2026-09-19 | ADR 0035, `research-api-surface.md`, `research-what-mods-are.md` |
| <https://raw.githubusercontent.com/anthropics/claude-code/main/mods/types/claude-code.d.ts> | Raw form, for the regeneration check (first line names the CLI that wrote it). | 2026-09-19 | go-no-go.md |
| <https://raw.githubusercontent.com/anthropics/claude-code/92ec78f2/mods/types/claude-code.d.ts> | Raw form pinned at the research commit; our counted catalog (38 + 54 events, 33 `classic.*`, 19 nouns). | 2026-09-19 | `research-api-surface.md` |
| <https://raw.githubusercontent.com/anthropics/claude-code/92ec78f2/mods/agents-md/README.md> | The `instructionFiles` option, its modes and default, and when the plugin stays out of a project that already loads its own `CLAUDE.md`. | 2026-09-19 | ADR 0035 |
| <https://github.com/anthropics/claude-code/blob/main/mods/sec-default/README.md> | How `sec-default` constrains, `prependPlugins` seating, and where `next.to` is allowed. | 2026-09-19 | `research-security-and-semantics.md`, `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/blob/92ec78f2/mods/sec-default/README.md> | The same, pinned. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://raw.githubusercontent.com/anthropics/claude-code/92ec78f2/mods/diff/hooks/hooks.json> | The manifest shape a mod-bearing `hooks.json` takes (the `modules` key). | 2026-09-19 | `research-authoring-and-testing.md`, `research-repo-fit.md` |
| <https://raw.githubusercontent.com/anthropics/claude-code/92ec78f2/mods/telemetry/hooks/hooks.json> | A second manifest instance, and which builds `telemetry` targets. | 2026-09-19 | `research-authoring-and-testing.md` |
| <https://raw.githubusercontent.com/anthropics/claude-code/92ec78f2/mods/telemetry/types/index.d.ts> | The `engine.create` noun-fold pattern a mod uses to add a noun to `$`. | 2026-09-19 | `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/commits/main/mods> | Commit history of the tree. Our count: first commit `d9c456d7` 2026-09-09, 83 commits at `92ec78f2`. | 2026-09-19 | `research-api-surface.md` |
| <https://api.github.com/repos/anthropics/claude-code/commits?path=mods> | The same history through the API, for the "has `mods/` moved?" check. | 2026-09-19 | go-no-go.md |
| <https://api.github.com/repos/anthropics/claude-code/commits?path=mods&per_page=100&sha=main> | The paginated form used to count the 83 commits. | 2026-09-19 | `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/commit/78c94cec> | The `mods/` commit on which files a hooks module may link. | 2026-09-19 | `research-contradictions-and-corrections.md` |
| <https://github.com/anthropics/claude-code/releases> | Release `v2.1.278`, published 2026-09-19T03:10:40Z: the version every `OBSERVED` and `BINARY` claim is pinned to. | 2026-09-19 | go-no-go.md |
| <https://api.github.com/repos/anthropics/claude-code/releases> | The same through the API. | 2026-09-19 | `research.md` |
| <https://api.github.com/repos/anthropics/claude-code/releases/tags/v2.1.269> | A single release lookup used while dating the version floor claims. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://api.github.com/repos/anthropics/claude-code/tags> | The newest repo tag, cross-checked against npm. | 2026-09-19 | go-no-go.md |
| <https://registry.npmjs.org/@anthropic-ai/claude-code/latest> | `latest` on npm, published 2026-09-19T01:48:59Z: the second half of the version cross-check. | 2026-09-19 | go-no-go.md |
| <https://raw.githubusercontent.com/anthropics/claude-code/main/README.md> | The repository's own front page, checked for any mods mention. | 2026-09-19 | `research-enablement-and-distribution.md` |

The shipped binary itself is not a URL. Every `BINARY` claim (the gate
`tengu_plugin_hooks_modules`, `hooksModulesFlagDefault` returning `false`, `prependPlugins`,
the 512-file / 8,388,608-byte limits) was read from the locally installed Claude Code 2.1.278 and is
re-derived by the greps in [go-no-go.md](go-no-go.md).

## Anthropic staff statements

Two of the five seed X posts the research started from are staff and sit here; the other three are
community posts and sit in the Community table. All five are marked **seed**. `poteat` is staff by
disclosed inference, not by confirmed metadata; everything attributed to that account is from
GitHub, never from X.

| Link | What we used it for | As of | Used by |
|---|---|---|---|
| <https://x.com/bcherny/status/2099551291601248485> | **Seed.** Boris Cherny, 2026-09-14: the mods landing announcement and a community Tetris mod. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://x.com/trq212/status/2101009393731223817> | **Seed.** Thariq, 2026-09-18: AGENTS.md support and its relation to mods. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://x.com/ClaudeDevs/status/2095572891941351550> | Official account, 2026-09-03: the Function Hooks announcement and its shipped status at that date. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://x.com/bcherny/status/2095590515765060076> | bcherny, 2026-09-03: the early look at extensibility. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://x.com/trq212/status/2101009392611278961> | The first post of the 2026-09-18 AGENTS.md thread, and the version it names. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://x.com/trq212/status/2092302273099796842> | An earlier Claude Code post by the same staff account, swept for mods mentions. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://github.com/user-attachments/files/31802150/EXTERNAL.Function.Hooks.Core.Architecture.pdf> | The 10-page design document attached to issue #91870, and its byline. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://github.com/user-attachments/assets/2fad9a87-d37f-4e00-9d4e-1aadf9326e77> | The cheat sheet attached to the Community Update, listing affordances on v267/v268. We observed it served as SVG despite the `.png` markdown. | 2026-09-19 | `research-surfaces.md` |

### Comments in issue #91870 cited by permalink

Each row is a permalink to a comment the report relies on. All but one are `poteat`'s; the
exception is noted in the GitHub issues table below, because its author is not staff. The issue
body is edited in place, so re-read the body as well as the comments.

| Link | What we used it for | As of | Used by |
|---|---|---|---|
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5530356661> | How `$` mediates events, and what that lets an admin audit, allowlist, deny, or log. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5530555431> | The onion model of hook ownership by registration order. | 2026-09-19 | `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5531058610> | The planned coverage of `tool.call` across MCP and non-MCP tools. | 2026-09-19 | `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5531157307> | What the model sees when a hook rewrites, and calling `next` more than once. | 2026-09-19 | `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5532000239> | The in-process performance claim. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5532500675> | First of four recorded positions on fail-open and re-dispatch; also the surface roadmap. | 2026-09-19 | `research-security-and-semantics.md`, `research-surfaces.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5533138495> | Second position on failure handling. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5539280904> | Packaging, the static scan, and OTEL intent. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5541093682> | First mention of `/plugin-types`. | 2026-09-19 | `research-authoring-and-testing.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5546290346> | Isolation's place in the contract, and `deny` after `next(e)`. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5553458185> | Third position: the skip cases, and the declarative fail-closed policy question. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5560061162> | What `validate` checks. | 2026-09-19 | `research-authoring-and-testing.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5560100559> | Whether a `tool.call` hook sees tool calls made inside a subagent. | 2026-09-19 | `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5561046073> | `$.process.run` and `$.http.fetch` as non-TypeScript escape hatches. | 2026-09-19 | `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5574036379> | The `classic.*` bridge events and the tier list. | 2026-09-19 | `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5588686533> | Fourth position: the `.catch` proposal the Sep 9 cheat sheet then ships. | 2026-09-19 | ADR 0035, `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5607792448> | The intended scope of `prompt.submit`. | 2026-09-19 | `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5609917069> | What `/plugin-types` lists once the flag is enabled. | 2026-09-19 | `research-authoring-and-testing.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5618866247> | Concurrency of `tool.check` guards versus `tool.call` guards. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5638914414> | Advice-style sugar, and which event may yield. | 2026-09-19 | `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5702935782> | 2026-09-16 restatement of the fail-closed spelling with `on(...).catch(...)`. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5734700291> | AGENTS.md as a built-in mod. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5738020815> | 2026-09-19: whether mods can set their own registration order, and the tier names. | 2026-09-19 | `research-what-mods-are.md` |
| <https://github.com/anthropics/claude-code/issues/91870#issuecomment-5666255143> | The comment bcherny's community-update link resolves to. Authored by `sezaakgun`, `author_association: NONE`: a community Tetris demo, not an Anthropic update. Tiering by "linked from a staff post" misfiles it. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://api.github.com/repos/anthropics/claude-code/issues/91870/comments> | How all 203 comments were fetched and grepped (for `desktop`, for install commands). | 2026-09-19 | `research-surfaces.md`, `research-enablement-and-distribution.md` |

## Official docs and changelog, checked for absence

Every row here was checked for the absence of any mods or function-hooks mention. The surface rows
also point at the pages the surface matrix rests on. Criterion 2 of the go check re-runs the
corpus sweeps; they are first-mention detectors, never availability checks. The `docs/en/*` pages
were read as page bodies inside `llms-full.txt` by one lane and individually fetched by another, so
per-page fetch provenance differs between lanes.

| Link | What we used it for | As of | Used by |
|---|---|---|---|
| <https://code.claude.com/docs/llms-full.txt> | Our sweep of all 197 English documentation pages, 9,590,632 bytes: **0 hits** for `function hook`, `hooks module`, `plugin-types`, `prependPlugins`, `appendPlugins`, `engine.create`, `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`, `sec-default`, `next.to(`, `"modules"`. Live controls (`plugin-dir` 67) prove the sweep works. | 2026-09-19 | ADR 0035 (criterion 2), go-no-go.md, `plugin-philosophy.md` |
| <https://code.claude.com/docs/llms.txt> | The curated index. Recorded so a later agent does not grep it by mistake: always grep `llms-full.txt`. | 2026-09-19 | go-no-go.md |
| <https://code.claude.com/docs/sitemap.xml> | How the 197-page count was established. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md> | Our sweep of 7,158 lines, `## 2.1.278` down to `## 0.2.21`: **0 hits** for the same terms, and word-bounded `mods?` → 0. | 2026-09-19 | ADR 0035, `plugin-philosophy.md` |
| <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md> | Raw form, for the greppable criterion check. | 2026-09-19 | go-no-go.md |
| <https://raw.githubusercontent.com/anthropics/claude-code/92ec78f2/CHANGELOG.md> | The same pinned at the research commit; the 2.1.277 AGENTS.md entry, which our grep found does not say "mod". | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://code.claude.com/docs/en/plugins-reference> | The plugin manifest reference: our sweep found no `modules` key; the plugin-root dependency install rule. | 2026-09-19 | `research-repo-fit.md` |
| <https://code.claude.com/docs/en/plugins> | The plugin system as documented; our sweep found no mods surface. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://code.claude.com/docs/en/hooks> | Classic hooks as documented; the contract a `classic.*` bridge event mirrors. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://code.claude.com/docs/en/plugin-marketplaces> | Distribution as documented; the one bare `plugin test` string in the corpus is the English word "testing" on this page. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://code.claude.com/docs/en/env-vars> | Our check that `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` is not listed. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://code.claude.com/docs/en/managed-settings> | Managed settings as documented; our check that `prependPlugins` / `appendPlugins` are absent. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://code.claude.com/docs/en/server-managed-settings> | Which surfaces fetch server-managed settings (surface matrix input). | 2026-09-19 | `research-surfaces.md` |
| <https://code.claude.com/docs/en/desktop> | How the Desktop Code tab relates to the CLI engine and `~/.claude` config, and the Windows environment inheritance the Desktop probe used. | 2026-09-19 | `research-surfaces.md`, experiments.md |
| <https://code.claude.com/docs/en/vs-code> | How the VS Code extension runs the CLI (surface matrix input). | 2026-09-19 | `research-surfaces.md` |
| <https://code.claude.com/docs/en/jetbrains> | How JetBrains runs `claude`, which makes it a `terminal` surface. | 2026-09-19 | `research-surfaces.md` |
| <https://code.claude.com/docs/en/claude-code-on-the-web> | Web and mobile Code clients on cloud sessions, and `/plugin` there. | 2026-09-19 | `research-surfaces.md` |
| <https://code.claude.com/docs/en/claude-projects> | Cloud sessions and their plugin delivery path. | 2026-09-19 | `research-surfaces.md` |
| <https://code.claude.com/docs/en/agent-sdk/plugins> | How the SDK loads plugins. | 2026-09-19 | `research-surfaces.md` |
| <https://code.claude.com/docs/en/skills> | Which plugin components reach Cowork and cloud sessions. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://code.claude.com/docs/en/model-config> | Swept in the 197-page term sweep; no mods mention. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://code.claude.com/docs/en/errors> | The early-access and feature-flag error entries. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://code.claude.com/docs/en/plugin-evals> | How `claude plugin eval` discloses its sandboxing, the comparison a mods warning lacks. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://www.anthropic.com/news/claude-code-plugins> | Not a pointer (correlate only): the canonical announcement URL, which we observed 308-redirecting to the blog post below. For the topic, see [Plugins](https://code.claude.com/docs/en/plugins). | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://claude.com/blog/claude-code-plugins> | Not a pointer (correlate only): the plugins launch announcement, published 2025-10-09; our check found no mods mention. For the topic, see [Plugins](https://code.claude.com/docs/en/plugins). | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://claude.com/blog/cowork-is-now-claude> | Not a pointer (correlate only): the 2026-09-16 Cowork/Chat merge announcement; our check found it does not name Claude Code. No docs page covered the merge as of 2026-09-19. | 2026-09-19 | `research-surfaces.md` |
| <https://claude.com/blog/cowork-plugins> | Not a pointer (correlate only): plugins in Cowork and how they sync. For the topic, see [Use plugins in Claude](https://support.claude.com/en/articles/13837440-use-plugins-in-claude) below. | 2026-09-19 | `research-surfaces.md` |
| <https://claude.com/docs/cowork/changelog> | Cowork's own changelog: no mods mention. | 2026-09-19 | `research-surfaces.md` |
| <https://claude.com/docs/connectors/building/mcpb> | The MCP bundle manifest specification, read as the adjacent packaging format. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://support.claude.com/en/articles/13837440-use-plugins-in-claude> | Which components of a synced plugin load in Cowork. | 2026-09-19 | `research-surfaces.md` |
| <https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork> | What Cowork runs its sessions on. | 2026-09-19 | `research-surfaces.md` |
| <https://support.claude.com/en/articles/12138966-release-notes> | Consumer-facing release notes: no mods mention. | 2026-09-19 | `research-surfaces.md` |
| <https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop> | Named by the `.mcpb` page's cross-reference. Reached only as a search snippet, never fetched. | not recorded | `research-surfaces.md` |

## GitHub issues and pull requests

| Link | What we used it for | As of | Used by |
|---|---|---|---|
| <https://github.com/anthropics/claude-code/issues/91870> | The mods roadmap thread, opened 2026-09-03. OPEN, 203 comments. The body is edited in place and carries the self-dated "Sep 9, 2026" Community Update and the public `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` acknowledgement. | 2026-09-19 | ADR 0035, go-no-go.md, `research-roadmap-and-staff-statements.md` |
| <https://github.com/anthropics/claude-code/issues/92533> | **The blocking defect.** Registering any `tool.call` hook on Bash breaks `Agent(isolation: "worktree")`; a passthrough `next(e)` is enough. OPEN, filed 2026-09-06 on 2.1.263 (macOS), one independent Windows reproduction at 2.1.272 in the thread, and our second Windows reproduction run locally on 2026-09-19 at 2.1.278 (`experiments.md` E2); no staff reply. | 2026-09-19 | ADR 0035 (criterion 3), go-no-go.md, experiments.md, `plugin-philosophy.md`, `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/issues/92675> | Plugin-native `PreToolUse` hooks auto-discovered via `hooks/hooks.json` reported not enforced in interactive sessions. OPEN, 0 comments. Gates the story that `hooks` and `modules` in one manifest both fire. | 2026-09-19 | go-no-go.md, `research-security-and-semantics.md` |
| <https://github.com/anthropics/claude-code/pull/93215> | The pull request that added `mods/`, opened 2026-09-09T22:31:07Z and self-merged at 22:34:33Z: the evidence behind the disclosed staff-by-inference call on `poteat`. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://github.com/anthropics/claude-code/issues/92469> | Generated-type incompleteness. OPEN. | 2026-09-19 | go-no-go.md, `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/92440> | Generated-type drift. OPEN. | 2026-09-19 | go-no-go.md, `research-api-surface.md` |
| <https://github.com/anthropics/claude-code/issues/95328> | A `session.compact` hook's compaction undone on resume. OPEN. | 2026-09-19 | go-no-go.md, `research-security-and-semantics.md` |
| <https://github.com/oven-sh/bun/pull/42768> | The runtime goal a staff comment links to when discussing node limits and WebAssembly. | not recorded (linked from a staff comment) | `research-api-surface.md` |
| <https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md> | The MCP bundle manifest, compared against the plugin manifest as a distribution alternative. | 2026-09-19 | `research-enablement-and-distribution.md` |

## Community

Third-party evidence. Nothing here outranks a first-party source; where a community claim and a
first-party source disagreed, the first-party source won.

| Link | What we used it for | As of | Used by |
|---|---|---|---|
| <https://x.com/halluton/status/2099640486130835845> | **Seed.** A reply in the bcherny post's chain, by the author of the `Mindful-Claude` mod. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://x.com/Voxyz_ai/status/2099564071972450641> | **Seed.** A note tweet relaying bcherny on early access and API stability, carrying a circulated prompt template that points Claude at documentation that does not exist. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://x.com/dani_avila7/status/2100245908893868522> | **Seed.** A third-party adopter's account of modifying Claude Code's internal functions, and the plan to distribute mods through aitmpl.com. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://xtomd.com/api/fetch> | The no-auth X-to-Markdown converter every X post was fetched and re-fetched through; it resolved 9 of 9 posts. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://threadreaderapp.com/thread/2099551291601248485.html> | Attempted unroll of the bcherny seed. **Failed**: HTTP 200 landing page, no post content. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://threadreaderapp.com/thread/2100245908893868522.html> | Attempted unroll of the dani_avila7 seed. **Failed**, same shape. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://threadreaderapp.com/thread/2101009393731223817.html> | Attempted unroll of the trq212 seed. **Failed**, same shape. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://www.practicalsystems.io/blog/claude-code-function-hooks-mods-layer> | The substantial independent migration report (2026-09-17, Windows, 2.1.273/2.1.274): the silent-inert failure mode where the module is never registered, and the version-canary and denial-test lessons. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://wavect.io/blog/claude-mods-function-hooks/> | A third-party write-up; the version it names is the one its inspected declarations identify, which is not a floor. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://claudefa.st/blog/tools/hooks/function-hooks> | A third-party write-up stating no version floor. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://www.aitmpl.com/mods/> | A mods component library; its version floor claim is uncorroborated. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://github.com/davila7/claude-code-templates> | The same library's repository, with an `npx` installer: evidence that distribution is happening outside any marketplace. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://github.com/kunchenguid/firstmate> | A third-party adopter shipping a hooks module with tests; its `hooks.json` documents an exact-value activation guard, as does the same author's `compact-adviser`. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://github.com/halluton/Mindful-Claude> | A third-party mod; the only source naming an install path and a version floor. Neither is corroborated by staff. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://github.com/pleaseai/honmoon> | A third-party mod repository, counted in the adopter census. | 2026-09-19 | `research-enablement-and-distribution.md` |
| <https://github.com/sezaakgun/cc-arcade> | The Tetris-in-Claude mod bcherny's post points at. | not recorded (linked from comment 5666255143) | `research-roadmap-and-staff-statements.md` |
| <https://github.com/shcv/harness-investigations> | A third-party reverse-engineered changelog, dating `claude plugin test` as absent in 2.1.270 and present in 2.1.271. | 2026-09-19 | `research-authoring-and-testing.md` |
| <https://hn.algolia.com/api/v1/search?query=%22claude%20mods%22&tags=story> | Hacker News attention: the mods story is 3 points, 0 comments. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://hn.algolia.com/api/v1/search?query=%22function+hooks%22+claude&tags=story> | The same sweep on the engineering term. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://www.reddit.com/r/ClaudeCode/search.json?q=function+hooks+OR+mods> | Attempted Reddit sweep; **network-blocked, unchecked**, recorded as a gap rather than a null result. | 2026-09-19 | `research-roadmap-and-staff-statements.md` |
| <https://simonwillison.net/2026/Sep/16/one-claude/> | Secondary coverage of the Cowork/Chat merge. | 2026-09-19 | `research-surfaces.md` |
| <https://techcrunch.com/2026/09/16/anthropic-merges-claude-chat-and-cowork-in-one-interface/> | Secondary coverage of the same merge; does not carry the two-mode claim. | 2026-09-19 | `research-surfaces.md` |
| <https://9to5mac.com/2026/09/16/> | The one secondary outlet of three that carries the two-mode claim, which no first-party source supports. | 2026-09-19 | `research-surfaces.md` |
| <https://www.marktechpost.com/2026/09/17/anthropic-launches-claude-code-projects-in-beta-parallel-cloud-sessions-that-keep-running-after-you-close-your-laptop/> | Indicative of the 2026-09-17 Projects beta date. Reached as a search snippet, never fetched, so not an independent corroborator. | not recorded | `research-surfaces.md` |
| <https://nodejs.org/api/vm.html> | Node's own position on `node:vm` as a security mechanism, the support for this corpus's `INFERRED` non-containment reading. | 2026-09-19 | `research-security-and-semantics.md` |
| <https://devblogs.microsoft.com/oldnewthing/20050607-00/?p=35413> | The essay a staff comment cites when refusing a numeric priority system. | not recorded (linked from a staff comment) | `research-repo-fit.md` |

## Not indexed, and why

- `http://aitmpl.com`: the bare host, duplicated by the `/mods/` page above.
- `https://old.reddit.com/`: the fallback host for a sweep that was network-blocked; the search URL
  above is the one that records the gap.
- `https://api.anthropic.com/api/event_logging/v2/batch`: an endpoint read out of the binary, not a
  source anyone fetched.
- `https://github.com/anthropics/claude-code/issues/91870#issuecomment` and
  `...#issuecomment-`: truncated prose fragments, not links.
- `https://threadreaderapp.com/thread/{2099551291601248485`: a template artifact; the resolved form
  is indexed above.
- `https://hn.algolia.com/api/v1/search?query=%22claude+mods%22&tags=story`: the same query as the
  space-encoded form above.
