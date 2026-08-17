---
topic: claude-code-workflows-context-cost-and-disable
section: evidence-and-gaps
abstract: Fetch log, conflicts, recency verdict against Claude Code 2.1.233, and the explicit list of what could not be verified — chiefly runtime deferral of the Workflow tool and first-hand access to the token measurement.
claims:
  - claim: "The latest upstream Claude Code release at time of research is 2.1.233, confirmed from the upstream CHANGELOG fetched this turn; the Tier 0 binary read is v2.1.232, one patch behind."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "Anthropic (GitHub upstream repo)"
      - url: "local: `claude --version` -> 2.1.232 (Claude Code)"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://code.claude.com/docs/en/tools-reference"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
  - claim: "Neither `disableWorkflows` nor `CLAUDE_CODE_DISABLE_WORKFLOWS` appears anywhere in the upstream CHANGELOG, which covers 0.2.21 through 2.1.233."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "Anthropic (GitHub upstream repo)"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
produced_by: phase-1-through-4
---

# Evidence, conflicts, recency, and what could NOT be verified

All fetches **2026-08-17**.

## Recency status (outcome-gate criterion 6)

| Item | Value |
|---|---|
| Confirmed latest release | **2.1.233** |
| How confirmed | upstream `CHANGELOG.md` fetched this turn; top heading is `## 2.1.233` |
| Changelog range | `0.2.21` → `2.1.233` |
| Tier 0 binary read | **2.1.232** (one patch behind) |
| Verdict | **current** — no major bump; `tools-reference` independently references "v2.1.233 and later" behavior, consistent with the changelog head |

`https://api.github.com/repos/anthropics/claude-code/releases/latest` and the tags endpoint both
returned empty through this environment's proxy, so the release stream was confirmed from
`CHANGELOG.md` on `main` instead. Version-gated claims carried by the docs (workflows require
v2.1.154; `workflowSizeGuideline` v2.1.219; `ultracode` effort v2.1.203; symlink hardening v2.1.216;
keyword-origin restriction v2.1.210) are all below the confirmed head and are therefore in force.

**Changelog gap worth flagging:** the workflows *disable* surface has no changelog entry at all.
`grep -i 'disableWorkflows\|CLAUDE_CODE_DISABLE_WORKFLOWS'` over the whole 513 KB changelog returns
nothing, though 50 other workflow lines exist (including the `disableBundledSkills` addition and the
`workflowSizeGuideline` addition). The keys are documented in the settings and env-var references but
were never announced. A skill that tracks these keys should pin the docs pages, not the changelog.

## Fetch log

One entry per fetch per claim. Rungs per the artifact ladder: 1 deepest artifact, 2 API/platform
reference, 3 product docs, 4 changelog, 5 announcement, 6 third-party.

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| Feature definition & components | `https://code.claude.com/docs/sitemap.xml` | — (enumeration surface) | Bash/curl | carries the claim (187 en pages; exhaustive for this host's pages) |
| Feature definition & components | `https://code.claude.com/docs/en/workflows` | 3 | WebFetch | carries the claim |
| Feature definition & components | `https://code.claude.com/docs/en/plugins-reference.md` | 2 | Bash/curl + grep | carries the claim |
| Feature definition & components | `https://code.claude.com/docs/en/commands.md` | 3 | Bash/curl + grep | carries the claim |
| Feature definition & components | `node_modules/@anthropic-ai/claude-code/sdk-tools.d.ts` | 1 | Read/grep | carries the claim (WorkflowInput/WorkflowOutput) |
| Feature definition & components | upstream `CHANGELOG.md` | 4 | Bash/curl | 2.1.233 (2026-08 head) — current |
| Workflow tool exists / permission | `https://code.claude.com/docs/en/tools-reference.md` | 2 | Bash/curl + grep | carries the claim (`Workflow`, Permission required: Yes) |
| Tool description size | `claude.exe` v2.1.232 offsets 300499041–300518629 | 1 | Bash/dd/grep | carries the claim (19,588 bytes) |
| Tool description size | `https://github.com/anthropics/claude-code/issues/66073` | 6 | WebFetch | fetched and searched, does not carry the claim (no Workflow mention; gives 16k-token built-in total) |
| Token measurement ~5,391 | `https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt` | 6 | WebFetch → curl → WebSearch | **unreachable after escalation** for direct read (EGRESS_BLOCKED, then HTTP 403); content obtained via WebSearch synthesis only — Gap |
| Prefix vs deferred | `claude.exe` `tengu_non_deferrable_builtins`, `nD_=[]`, `qB()` | 1 | Bash/dd/grep | carries the claim (server-controlled; local default empty) |
| Prefix vs deferred | `https://code.claude.com/docs/en/agent-sdk/tool-search` | 2 | sitemap-enumerated, not fetched | **unresolved** — see Gaps |
| Prefix vs deferred | upstream `CHANGELOG.md` | 4 | Bash/curl | 2.1.233 — current (no deferral change since) |
| Disable spellings | `https://code.claude.com/docs/en/settings.md` | 2 | Bash/curl + grep | carries the claim (line 274) |
| Disable spellings | `https://code.claude.com/docs/en/env-vars.md` | 2 | Bash/curl + grep | carries the claim (line 256) |
| Disable spellings | `https://code.claude.com/docs/en/workflows` | 3 | WebFetch | carries the claim ("Turn workflows off") |
| Disable spellings | `claude.exe` `Fkr()` / `jD()` / settings schema | 1 | Bash/dd/grep | carries the claim (+ undocumented `enableWorkflows`) |
| Disable spellings | upstream `CHANGELOG.md` | 4 | Bash/curl + grep | 2.1.233 — current; **no entry for either key** (recorded as a gap, not an invalidation) |
| Scope & precedence | `https://code.claude.com/docs/en/settings.md` exceptions table | 2 | Bash/curl + sed | carries the claim (disableWorkflows absent from exceptions) |
| Scope & precedence | `https://code.claude.com/docs/en/server-managed-settings.md` | 2 | Bash/curl + grep | carries the claim (no-merge rule, source ranking) |
| Payload removal | `claude.exe` `isEnabled:()=>jD()` | 1 | Bash/dd | carries the claim |
| Payload removal | `claude.exe` `o.filter((c,u)=>a[u])` and `...B3r&&jD()?[B3r]:[]` | 1 | Bash/dd | carries the claim |
| Payload removal | `https://code.claude.com/docs/en/workflows` | 3 | WebFetch | fetched and searched, does not carry the claim (behavioral consequences only) |
| Payload removal | upstream `CHANGELOG.md` | 4 | Bash/curl | 2.1.233 — current |
| /context attribution | `claude.exe` UI label literals | 1 | Bash/dd | carries the claim |
| /context attribution | `https://code.claude.com/docs/en/commands.md` | 3 | Bash/curl + grep | carries the claim (`/context` description) |
| /context attribution | `https://code.claude.com/docs/en/context-window.md` | 3 | Bash/curl + grep | fetched and searched, does not carry the claim (illustrative visualization) |
| Plan gating | `https://code.claude.com/docs/en/feature-availability.md` | 3 | Bash/curl + grep | carries the claim |

Rung-1 accounting: for the behavioral claims the deepest first-party artifact is the shipped binary
and `sdk-tools.d.ts`, both of which were reached and read. For the doc-only claims (spellings,
precedence, plan gating) rung 1 **does not exist for this claim class** — Anthropic ships no deeper
artifact than the reference pages plus the binary, and both were swept.

## Conflicts

**C1 — resolved.** `docs/en/workflows` names `disableWorkflows` and `CLAUDE_CODE_DISABLE_WORKFLOWS`,
while a `WebFetch` summary of `docs/en/settings` and `docs/en/env-vars` reported both keys absent.
**Resolution: the summaries were wrong.** Downloading both pages (334 KB and 404 KB of markdown) and
grepping them on disk found `disableWorkflows` at settings line 274 and
`CLAUDE_CODE_DISABLE_WORKFLOWS` at env-vars line 256. The tell was that the same env-vars page
demonstrably contains `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS`, which the summary also missed. Cause
is truncation, not a docs inconsistency. **This is a methodology red flag for the consuming skill,
recorded in the disable-mechanisms sidecar.**

**C2 — resolved.** The `tools-reference` `Workflow` row carries `Yes` in its final column, which
could be misread as "always loaded". Reading the table header shows the column is **"Permission
required"**. It says nothing about prefix residency.

**C3 — noted, not a conflict.** Docs say `CLAUDE_CODE_DISABLE_WORKFLOWS` should be "set to `1`";
Tier 0 shows a bare truthiness test, so `0`/`false` also disable. The docs are not wrong about the
supported usage, but they under-describe the parsing. Recorded as a caveat, not a contradiction.

## Gaps — what I could NOT verify

1. **Whether the `Workflow` tool is actually deferred behind `ToolSearch` in a default interactive
   session.** The eligibility list is resolved from server-side config (`tengu_non_deferrable_builtins`
   / `non_deferrable_builtins`) whose value I cannot read from the client. The compiled default is
   empty and `/context` has a `System tools (deferred)` row, so deferral is *possible*; the empirical
   diff shows the schema present in the initial request in `claude -p`. **Unverified for interactive
   sessions.** Checked: the binary, `tools-reference`, `commands`, `context-window`. **Unchecked:**
   `docs/en/agent-sdk/tool-search` and `docs/en/mcp#scale-with-mcp-tool-search`, which I enumerated
   from the sitemap but did not fetch — those are the first places to look next.
2. **First-hand read of the ~5,391-token measurement.** `www.aihero.dev` is egress-blocked here for
   both `WebFetch` (`EGRESS_BLOCKED`) and `curl` with a browser UA (HTTP 403). The full escalation
   ladder was walked; the content reached me only through WebSearch synthesis. **Single pool, never
   read directly — MEDIUM confidence.** Reproducible locally by the described diff.
3. **Exact tokenized size** of the description. I measured 19,588 **bytes**; token counts are
   tokenizer- and model-dependent. The byte count is exact, the token figure is an estimate.
4. **`enableWorkflows` is undocumented.** Present in the binary's settings schema with a describe
   string; absent from the settings reference page. Its precedence relative to `/config` is inferred
   from `jD()`'s ordering, not from prose.
5. **The Claude Code admin-settings page toggle** (<https://claude.ai/admin-settings/claude-code>)
   is documented but requires an authenticated org account; I could not observe it. Its equivalence
   to managed `disableWorkflows` is the docs' claim, unverified independently.
6. **Desktop-app and IDE-extension behavior.** The docs assert "the same disable settings apply on
   every surface"; I verified only the CLI.
7. **No Anthropic maintainer statement** on payload-vs-refusal was found. Issue #66073 (the closest
   community request) was closed as not planned with no visible maintainer reply, and does not
   mention workflows. Checked: `anthropics/claude-code` issue #66073, the docs corpus, the changelog.
   **Unchecked:** the wider issue tracker by search (the GitHub MCP server in this session is scoped
   to a single unrelated repo, and `api.github.com` issue reads returned 403 through the proxy).

## Outcome-gate result (self-graded rows only)

| # | Criterion | Result |
|---|---|---|
| 1 | Every claim has ≥1 Tier 0/1 captured this turn | **PASS** |
| 2 | No claim is all-Tier-2 | **PASS** — the one Tier-2-dependent number is flagged MEDIUM and marked a Gap |
| 3 | Phase 2/3 queries trace to numbered gaps | **PASS** |
| 5 | Falsification query ran and is recorded | **PASS** — targeted "disabling does not reduce context / tool still loaded"; it failed to falsify and instead surfaced the corroborating request-body diff |
| 6 | Recency gate satisfied | **PASS** — 2.1.233 confirmed this turn, verdict `current` |
| 9 | Artifact ladder accounted for per claim | **PASS** — see fetch log |
| 10 | Absences name checked and unchecked sources | **PASS** — see Gaps |
| 11 | Coverage ledger fully marked | **PASS** — `check-coverage-complete.sh` exit 0 |
| 4, 7 | independence + HIGH confidence | **deferred to verifier** (not self-graded) |
| 8 | Project fit | **deferred to parent** |
