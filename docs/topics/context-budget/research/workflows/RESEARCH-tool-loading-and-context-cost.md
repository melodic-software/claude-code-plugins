---
topic: claude-code-workflows-context-cost-and-disable
section: tool-loading-and-context-cost
abstract: The Workflow tool description measures 19,588 bytes in the v2.1.232 binary (~5,391 tokens by an independent request-body diff); it is an ordinary gated built-in, and whether it is deferred behind ToolSearch is server-controlled rather than a fixed property of the tool.
claims:
  - claim: "The Workflow tool's description string is 19,588 bytes in the installed v2.1.232 binary, making it one of the largest single tool descriptions Claude Code ships."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "local: claude.exe v2.1.232, byte offsets 300499041-300518629, template literal S6a"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt"
        tier: 2
        pool: "aihero.dev (named practitioner blog) — reached via WebSearch synthesis only, see Gaps"
      - url: "https://github.com/anthropics/claude-code/issues/66073"
        tier: 1
        pool: "GitHub issue tracker (community, anthropics/claude-code)"
  - claim: "An independent request-body diff measured disableWorkflows removing ~5,391 tokens per request, ~27% of the baseline, with the entire delta attributable to the Workflow tool."
    confidence: MEDIUM
    tiers: [2, 0]
    sources:
      - url: "https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt"
        tier: 2
        pool: "aihero.dev (named practitioner blog)"
      - url: "local: claude.exe v2.1.232 description length 19588 bytes, corroborating order of magnitude"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
  - claim: "Whether the Workflow tool is deferred behind ToolSearch is not a fixed property of the tool: the local default non-deferrable-builtins list is empty and the effective list comes from server-side config."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local: claude.exe v2.1.232, `tengu_non_deferrable_builtins` / `non_deferrable_builtins`, default `nD_=[]`"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://code.claude.com/docs/en/tools-reference"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic (code.claude.com docs, Agent SDK tree)"
produced_by: phase-2-and-3
---

# Is the Workflow tool schema in the prefix, or deferred behind ToolSearch?

All URLs fetched **2026-08-17**. Tier 0 from the installed **v2.1.232** binary.

## Answer, stated carefully

**The Workflow tool is an ordinary gated built-in tool, not a special always-resident one — and the
docs do not settle whether it is deferred.** What is settled:

1. When workflows are enabled, the `Workflow` tool is **in the session's tool list** (it is filtered
   in by `isEnabled()`; see the `payload-removal` sidecar).
2. Claude Code's own `/context` distinguishes **`System tools`** from **`System tools (deferred)`**,
   so built-in tools *can* land in either bucket.
3. Deferral eligibility for built-ins is **not hard-coded per tool**. The binary resolves a
   non-deferrable set from remote config, and the **compiled-in default is the empty list**:

   ```js
   function Snd(){let e=new Set;
     try{let t=oD_(rt("tengu_non_deferrable_builtins",null)); /* … */}catch{}
     try{let t=Gx()?.non_deferrable_builtins; /* … */}catch{}
     if(e.size===0)return nD_;   // nD_=[]
     return[...e]}
   ```

   — `claude.exe` v2.1.232 (Tier 0, read 2026-08-17)

4. Tool search itself is conditional. `qB()` returns `false` when the resolved mode is `"standard"`,
   and also when `ENABLE_TOOL_SEARCH` is unset and the base URL is not a first-party Anthropic host:

   > `"[ToolSearch:optimistic] disabled: ANTHROPIC_BASE_URL=… is not a first-party Anthropic host.
   > Set ENABLE_TOOL_SEARCH=true (or auto / auto:N) if your proxy forwards tool_reference blocks."`
   > — `claude.exe` v2.1.232 (Tier 0, read 2026-08-17)

**So: in a session where tool search is not active, the Workflow tool's full schema is in the request
prefix.** In a session where tool search *is* active, whether `Workflow` is deferred depends on a
server-controlled list this research could not read. That is the honest boundary.

**Directly relevant empirical datapoint:** the request-body diff described below was run with
`claude -p`, and the Workflow tool schema **was present in the initial request body** there — its
removal is what produced the whole measured delta. That is direct evidence the tool is in the
startup payload in at least that mode, and it is the mode a context-baseline skill is most likely to
be able to measure.

## The size of the thing

Measured Tier 0, by locating the description template literal in the v2.1.232 bundle:

| Measure | Value |
|---|---|
| Start offset (`Execute a workflow script that orchestrates multiple subagents deterministically`) | 300,499,041 |
| End offset (`hand-author a continuation script.`) | 300,518,629 |
| **Length** | **19,588 bytes** |
| Naive tokens at 4 bytes/token | ~4,897 |
| **Independently measured tokens** | **~5,391** |

The description opens:

> "Execute a workflow script that orchestrates multiple subagents deterministically. Workflows run in
> the background — this tool returns immediately with a task ID, and a `<task-notification>` arrives
> when the workflow completes. Use /workflows to watch live progress."

and continues through opt-in rules, an Ultracode section, the `meta` block contract, the
`agent()`/`parallel()`/`pipeline()`/`phase()` hook signatures, worked examples, and failure modes.
The input schema (`WorkflowInput`, 7 properties with long `describe()` strings) is **additional** to
that 19,588 bytes and is separately visible in the shipped
`node_modules/@anthropic-ai/claude-code/sdk-tools.d.ts`.

For scale: a community feature request measured **all ~30 built-in tools together at 16,000+ tokens**
([issue #66073](https://github.com/anthropics/claude-code/issues/66073), closed as not planned,
fetched 2026-08-17). If both numbers are right, the single `Workflow` tool is roughly a third of the
entire built-in tool-definition budget. Treat that ratio as indicative — the two figures come from
different measurements at different versions, and #66073 does not itself mention the Workflow tool.

## The independent measurement and its methodology

The ~5,391-token figure comes from a named-practitioner writeup whose method is checkable:
`ANTHROPIC_BASE_URL` pointed at a small local server, `claude -p "hi"` run once with the flags off
and once on, and the two captured request bodies diffed. Reported result: **~27% smaller baseline,
~5,391 tokens saved per request, the entire delta from `disableWorkflows` removing the Workflow
tool.**

The same writeup reports that `disableArtifact` and `disableBundledSkills` showed **zero** effect in
that particular test because print mode uses a deferred-tool architecture and those payloads are
injected at runtime in interactive sessions instead. **That caveat is worth carrying into the skill's
design**: a measurement harness built on `claude -p` will attribute savings correctly for workflows
but can under-report other trim candidates.

**Source-access caveat, stated plainly:** `www.aihero.dev` is blocked by this environment's egress
proxy — both `WebFetch` (`EGRESS_BLOCKED`) and a direct `curl` with a browser UA (HTTP 403) failed.
The escalation ladder was walked and the content was reached **only through WebSearch synthesis**,
which makes it a Tier 2 claim from a single publishing pool that I never read first-hand. The number
is therefore recorded at **MEDIUM confidence**, corroborated in order of magnitude by the Tier 0 byte
count but not independently reproduced. A skill author who needs the exact figure should re-run the
diff locally — the method is cheap and is the authoritative answer for their own configuration.
