---
topic: tool-definitions-prefix-pruning
section: fetch-log
abstract: "Per-claim fetch log with artifact-ladder rungs and outcomes, the recency verdict against Claude Code 2.1.233, conflicts, and the enumerated gaps including two the run could not settle."
claims:
  - claim: "The recency gate is satisfied: latest upstream release 2.1.233 fetched this turn, no major bump, claims current."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 0
        pool: "anthropics/claude-code upstream repo"
      - url: "claude --version (2.1.232), run 2026-08-17"
        tier: 0
        pool: "direct tool output (this session)"
produced_by: phase-all
---

# Fetch log, recency, conflicts, gaps

All fetches performed **2026-08-17**. Doc pages were retrieved as raw markdown (Mintlify `.md`
variant) with `curl` and searched on disk, so quotes are exact rather than summarized.

## Artifact-ladder note

For this topic the ladder tops out at **rung 2 (platform/API reference)**. Rung 1 — a deeper
technical artifact such as a system or model card — **does not exist for this claim class**: the
subject is CLI/API configuration behavior, not model capability, and the exhaustive surfaces swept
for it were `code.claude.com/sitemap.xml` (187 English pages), `docs.claude.com/sitemap.xml` (2,834
URLs, redirecting to `platform.claude.com`), and the `anthropics/claude-code` repo's published
`CHANGELOG.md`. No first-party artifact class above the API reference indexes this subject.

## Fetch log

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| Built-in tool inventory (45 names) | `https://code.claude.com/docs/en/tools-reference.md` | 3 product docs | curl + local parse | carries the claim |
| tools-reference does not mark prefix vs deferred | same | 3 | grep over full page | fetched and searched, does not carry the claim (the absence IS the finding) |
| Prefix built-ins named only by example | `https://code.claude.com/docs/en/agent-sdk/tool-search.md` | 3 | curl + Read | carries the claim |
| Background-subagent closed tool list | `https://code.claude.com/docs/en/sub-agents.md` | 3 | curl + grep | carries the claim |
| Task tools dropped on newer models to save context | `https://code.claude.com/docs/en/tools-reference.md#task-tool-availability` | 3 | curl + sed | carries the claim |
| Session prefix/deferred split | deferred-tool system reminder + `ToolSearch` `select:` result, session 2.1.232 | — (Tier 0) | direct tool output | carries the claim |
| MCP tools deferred by default (verbatim) | `https://code.claude.com/docs/en/mcp.md` §Scale with MCP tool search | 3 | curl + grep | carries the claim |
| Only tool names enter context | `https://code.claude.com/docs/en/costs.md` §Reduce token usage | 3 | curl + grep | carries the claim |
| `searchHint` shown in deferred-tool list | `https://code.claude.com/docs/en/agent-sdk/typescript.md` | 2 API ref | curl + grep | carries the claim |
| `defer_loading` sends but withholds; prefix untouched | `https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md` | 2 API ref | curl + sed | carries the claim |
| Deferred defs excluded from system-prompt prefix | same | 2 | curl + grep | carries the claim |
| Ladder rung 1 for all above | model/system card | 1 | sitemap sweep ×2 + changelog | **does not exist** for this claim class |
| `ENABLE_TOOL_SEARCH` five values | `https://code.claude.com/docs/en/env-vars.md`; `mcp.md`; `agent-sdk/tool-search.md` | 3 + 2 | curl + grep | carries the claim |
| `alwaysLoad` server + per-tool `_meta` | `https://code.claude.com/docs/en/mcp.md` §Exempt a server from deferral | 3 | curl + sed | carries the claim |
| `alwaysLoad` SDK forms | `https://code.claude.com/docs/en/agent-sdk/typescript.md` | 2 | curl + grep | carries the claim |
| `alwaysLoad` introduced v2.1.121 | `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` | 4 changelog | curl + grep | carries the claim — **2.1.233 (2026-08, HEAD of main) — current** |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` strips `defer_loading` | `https://code.claude.com/docs/en/env-vars.md` | 3 | curl + grep | carries the claim |
| No settings.json key for tool search | `https://code.claude.com/docs/en/settings.md` (334 KB) | 3 | curl + grep (0 hits ×4 terms) | fetched and searched, does not carry the claim |
| `disabledTools` undocumented | 21 fetched first-party pages | 3 | grep (0 hits) | fetched and searched, does not carry the claim |
| `disabledTools` bug reports | `https://github.com/anthropics/claude-code/issues/30480`, `/66073` | 6 third-party | WebFetch | carries the claim (about the wrong key) |
| Bare vs scoped deny semantics | `https://code.claude.com/docs/en/permissions.md` | 3 | curl + grep | carries the claim |
| `--disallowedTools` bare-name removal | `https://code.claude.com/docs/en/cli-reference.md` | 3 | curl + grep | carries the claim |
| "removed from the request" (strongest wording) | `https://code.claude.com/docs/en/agent-sdk/permissions.md` | 2 API ref | curl + sed | carries the claim |
| `permissions.deny` glob semantics | `https://code.claude.com/docs/en/settings.md` §Permission settings | 3 | curl + sed | carries the claim |
| Bare-name deny reduces prefix bucket (empirical) | `claude -p "/context" --output-format json --disallowedTools ...` ×4 runs | — (Tier 0) | Bash + local CLI | carries the claim |
| Falsification: deny does NOT remove | WebSearch, targeted counter-query | 6 | WebSearch | fetched and searched, does not carry the claim (no counter-evidence found) |
| `/context` category granularity | `https://code.claude.com/docs/en/commands.md`; `context-window.md` | 3 | curl + grep | carries the claim |
| `claude -p "/context"` works | `claude -p "/context" --output-format json`, 2.1.232 | — (Tier 0) | Bash | carries the claim |
| `/context` in `-p` is undocumented | `https://code.claude.com/docs/en/headless.md`; `commands.md` | 3 | curl + grep | fetched and searched, does not carry the claim |
| `count_tokens` accepts `tools` | `https://platform.claude.com/docs/en/build-with-claude/token-counting.md` | 2 API ref | curl + grep | carries the claim |
| Tool-use system-prompt overhead table | `https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview.md` §Pricing | 2 | curl + sed | carries the claim |
| No chars-per-token rule; recount per model | `token-counting.md` + 21-page grep | 2 + 3 | curl + grep | carries the claim (the instruction), absence enumerated |
| OTel is result-level not definition-level | `https://code.claude.com/docs/en/monitoring-usage.md` | 3 | curl + grep | fetched and searched, does not carry the claim |
| 30-50 tools accuracy degradation | `https://code.claude.com/docs/en/agent-sdk/tool-search.md` | 3 | curl + Read | carries the claim |
| 10+/20+/200+ adoption thresholds | `tool-search-tool.md`; `manage-tool-context.md` | 2 | curl + sed/Read | carries the claim |
| Anthropic engineering blog on advanced tool use | `https://www.anthropic.com/engineering/advanced-tool-use` | 5 announcement | WebFetch, then curl | **unreachable after escalation** — see Gap 3 |

## Recency status

- **Upstream latest: 2.1.233**, read from `CHANGELOG.md` HEAD this turn. Local binary **2.1.232**.
- No major-version bump (2.x throughout). Docs `lastmod` values are 2026-08-13 to 2026-08-16, i.e.
  1-4 days old at fetch time — inside the 14-day window for an actively released tool.
- Changelog entries touching this topic were reviewed: 2.1.233 (Task tools dropped on newer models),
  2.1.221 (Agent Platform tool-search default), 2.1.227 (managed settings can keep tool search on),
  2.1.121 (`alwaysLoad` added). None invalidates a claim in this artifact.
- **Verdict: current.**

## Conflicts

1. **10+ vs ~20 vs 30-50 tool thresholds.** Three first-party numbers. Resolved in
   `RESEARCH-tool-count-thresholds.md`: they answer three different questions (payoff point, rule of
   thumb, accuracy knee), not one question three ways.
2. **"Deferred definitions are not in context" vs `/context` billing them 17.8k.** Resolved in
   `RESEARCH-deferral-mechanism.md`: the API excludes them from the *prefix* while the client still
   *sends* them in the `tools` array, and `/context` measures what the client sends. Not a
   contradiction, but the single most misreadable point in the topic.
3. **Issues #30480/#66073 vs the documented deny behavior.** Resolved: those used `disabledTools`, an
   undocumented key. Primary wins; the issues are evidence about a different thing.

## Gaps — claims NOT accepted, carried forward for the skill author

1. **Does the API bill for undiscovered deferred definitions?** The tool-search-tool page states
   deferred definitions are still sent and that definitions *search loads into context* count as
   input tokens, but says nothing about the ones never discovered. **Checked:** `tool-search-tool`,
   `token-counting`, `manage-tool-context`, `tool-use/overview`, `context-editing`, `costs`.
   **Unchecked:** `tool-use-with-prompt-caching`, the Messages API reference, the pricing page, and
   Anthropic support articles. *Settling evidence:* two `count_tokens` calls against an identical
   `tools` array with and without `defer_loading: true`, compared against a real Messages call's
   `usage.input_tokens`. This is directly testable and would materially change what the skill can
   claim about deferral's savings.
2. **`--tools` and the vanishing deferred bucket (run D).** `--tools "Bash,Edit,Read"` removed the
   `System tools (deferred)` line entirely, though the CLI reference says `--tools` "doesn't affect
   MCP tools". Most likely the MCP servers had not connected in that short `-p` run. *Settling
   evidence:* re-run with `MCP_CONNECTION_NONBLOCKING=0` and a longer prompt, and compare
   `/mcp` output across the two runs. Marked **UNVERIFIED** in `RESEARCH-permission-pruning.md`.
3. **Anthropic engineering blog — unreachable after escalation.** `WebFetch` returned
   `EGRESS_BLOCKED` for `www.anthropic.com`; `curl` returned HTTP 403 with `x-deny-reason:
   host_not_allowed`, i.e. this sandbox's egress proxy blocks the host, not the publisher. Escalation
   rungs available here (headless browser, managed scraper) are not connected this session. A
   WebSearch summary of the page was returned but is Tier 2 synthesis and is **not** used as a source
   for any accepted claim. Every claim it would have supported is already carried by Tier-1 pages, so
   no accepted claim depends on it. *Settling evidence:* fetch the page from an unrestricted network.
4. **Why two MCP servers landed on opposite sides of the split in this session.** Observed, not
   explained; the run did not read the servers' configuration. *Settling evidence:* inspect the
   resolved MCP config for an `alwaysLoad` flag on the prefix-loaded server.
5. **Whether `permissions.deny` bare-name removal has ever been separately confirmed for
   settings.json** (as opposed to `--disallowedTools`). The docs treat them as one rule engine and
   the SDK page names settings.json as a deny source, but this run's empirical tests used the CLI
   flag only. *Settling evidence:* repeat runs B/C with the rule in `.claude/settings.json`.

## Independence of corroborators — note for the verifier

Every first-party source here shares one publishing pool (Anthropic), across two hosts
(`code.claude.com`, `platform.claude.com`). Per this plugin's tier rules those are **not** fully
independent corroborators of each other. Independence for the load-bearing claims is supplied by:

- **Tier-0 direct measurement** in this environment (four matched `/context` runs, the session tool
  surface, `claude --version`, the `ToolSearch` expansion) — a different evidence kind, not a
  different publisher;
- the **upstream repo** (`CHANGELOG.md`), which is version-controlled and separately dated;
- **third-party issue reports** on GitHub, used only to characterize the `disabledTools` confusion.

The claim best supported across kinds is the bare-vs-scoped deny distinction: three first-party
pages, one upstream changelog context, and a controlled local experiment agree. The claim most
dependent on a single pool is the API-side statement that deferred definitions are still sent —
one page, no independent confirmation available without the API test in Gap 1.
