# RESEARCH — pruning tool definitions from a Claude Code session's request payload

## Task restatement

Research, for the author of a new marketplace skill that inventories and trims a session's fixed
startup context payload, **which trim actions actually reduce tokens versus merely block a tool**.
Six questions were posed: (1) the built-in tool inventory and the prefix/deferred split;
(2) how deferred loading works, including verifying the MCP page's "deferred by default" statement;
(3) whether any setting controls deferral (`alwaysLoad`, tool-search settings, an experimental flag),
verified against current docs rather than assumed; (4) the exact semantics of `disallowedTools` and
`permissions.deny` — schema removal or call blocking; (5) how to measure per-tool token cost
(`/context`, headless `claude -p "/context"`, the token-counting API, char-based estimation);
(6) official guidance on tool-count thresholds degrading tool-selection accuracy. Every claim carries
its source URL and fetch date; unverified items are marked.

## The short answer

**Three mechanisms, and only one of them deletes a schema from the request.**

| Mechanism | Effect on the request payload | Effect on the model's context |
|---|---|---|
| **Bare-name deny** (`permissions.deny: ["Edit"]`, `--disallowedTools "Edit"`, `--tools` allowlist) | **Definition removed from the request** | gone |
| **Tool-search deferral** (default for MCP + many built-ins) | definition **still sent** in the `tools` array every turn | withheld from the prefix; name only |
| **Scoped deny** (`permissions.deny: ["Bash(rm *)"]`) | definition **stays**, fully billed | present |

The one-line rule for the skill: **a deny rule with parentheses is a guard; a deny rule without
parentheses is a deletion.** Deferral is a context-window optimization that deliberately preserves
the cached prefix — it is not payload trimming.

Verified empirically this turn (Claude Code 2.1.232, four matched `claude -p "/context"` runs):
bare-name deny of three prefix-loaded tools moved `System tools` 18.1k → 13.7k; bare-name deny of
eight deferred tools plus `mcp__*` moved `System tools (deferred)` 17.8k → 10.3k.

## Sidecar abstracts

- **`RESEARCH-tool-inventory.md`** — The tools-reference page lists 45 built-in tools but never marks
  any as prefix-loaded vs deferred; the split is observable only per-session, and the doc list is not
  exhaustive of tools actually present.
- **`RESEARCH-deferral-mechanism.md`** — Tool search is on by default and MCP tools are deferred by
  default; deferral withholds a definition from the system-prompt prefix but the full schema is still
  transmitted in the request's tools array on every turn.
- **`RESEARCH-deferral-controls.md`** — Deferral is controlled by the ENABLE_TOOL_SEARCH env var
  (unset/true/auto/auto:N/false) and opted out per-server or per-tool via alwaysLoad; there is no
  settings.json key for either, and no experimental flag beyond CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS.
- **`RESEARCH-permission-pruning.md`** — The docs are explicit, not silent: a BARE tool name in
  disallowedTools or permissions.deny removes the definition from the request, while a SCOPED rule
  only blocks calls — confirmed verbatim and reproduced empirically.
- **`RESEARCH-measurement.md`** — /context reports category-level buckets including a separate System
  tools (deferred) line and works headlessly under claude -p; per-tool attribution is not offered,
  and the count_tokens API accepts a tools array so a skill can price one definition at a time.
- **`RESEARCH-tool-count-thresholds.md`** — Anthropic publishes explicit thresholds: tool-selection
  accuracy degrades beyond 30-50 loaded tools, tool search is advised past ~10-20 tools or 10k
  definition tokens, and 50 tools cost 10-20K tokens.
- **`RESEARCH-fetch-log.md`** — Per-claim fetch log with artifact-ladder rungs and outcomes, the
  recency verdict against Claude Code 2.1.233, conflicts, and the enumerated gaps including two the
  run could not settle.

## Section → file + anchor

| Question | Section | File | Anchor |
|---|---|---|---|
| Q1 tool inventory & split | tool-inventory | `RESEARCH-tool-inventory.md` | `#built-in-tool-inventory-and-the-prefixdeferred-split` |
| Q2 how deferral works | deferral-mechanism | `RESEARCH-deferral-mechanism.md` | `#how-deferred-tool-loading-works` |
| Q2 MCP "deferred by default" quote | deferral-mechanism | `RESEARCH-deferral-mechanism.md` | `#the-mcp-page-statement-verified-and-quoted` |
| Q2 deferred ≠ not sent | deferral-mechanism | `RESEARCH-deferral-mechanism.md` | `#the-load-bearing-subtlety-deferred--not-sent` |
| Q3 settings controlling deferral | deferral-controls | `RESEARCH-deferral-controls.md` | `#settings-that-control-deferral` |
| Q3 what does NOT exist | deferral-controls | `RESEARCH-deferral-controls.md` | `#4-what-does-not-exist--checked-and-reported-as-absence` |
| Q4 deny semantics | permission-pruning | `RESEARCH-permission-pruning.md` | `#disallowedtools-and-permissionsdeny--exact-semantics` |
| Q4 trim-action summary table | permission-pruning | `RESEARCH-permission-pruning.md` | `#summary-table-for-the-skills-trim-actions` |
| Q5 measurement | measurement | `RESEARCH-measurement.md` | `#how-to-actually-measure-per-tool-token-cost` |
| Q5 headless `/context` | measurement | `RESEARCH-measurement.md` | `#2-claude--p-context-headlessly--yes-it-works` |
| Q6 thresholds | tool-count-thresholds | `RESEARCH-tool-count-thresholds.md` | `#official-guidance-on-tool-count-thresholds-and-selection-accuracy` |
| Evidence, recency, gaps | fetch-log | `RESEARCH-fetch-log.md` | `#fetch-log-recency-conflicts-gaps` |
| Coverage ledger | — | `research-checklist.md` | — |

## Next-stage handoff

### Settled — safe to build the skill on

1. **Bare-name deny is the only supported action that removes a definition from the request.** Works
   via `permissions.deny` (settings.json), `--disallowedTools` (CLI), the SDK `disallowedTools`
   option, and agent/plugin-agent frontmatter. Globs `"*"` and `"mcp__*"` work in the tool-name
   position. `EndConversation` cannot be removed while any other tool remains.
2. **Scoped rules never shrink the payload.** A skill reporting savings for `Bash(rm *)` would be
   wrong.
3. **`--tools` is an allowlist over built-ins** and is the compact way to express a large trim; it
   does not affect MCP tools.
4. **Deferral is already on by default** for MCP tools and many built-ins. There is little headroom
   to "defer more" in a default Claude Code session — the skill's leverage is deny rules and
   `alwaysLoad` audits, not enabling deferral.
5. **`alwaysLoad` is the anti-pattern to hunt for.** Any MCP server carrying it forces every one of
   its tools into the prefix regardless of `ENABLE_TOOL_SEARCH`, and adds a startup wait. Auditing
   for stray `alwaysLoad` is a high-value, low-risk check.
6. **`/context` is the measurement surface**, it separates `System tools` from `System tools
   (deferred)`, and `claude -p "/context" --output-format json` returns it with zero API cost.
   Per-tool numbers come from differencing two runs.
7. **Do not ship a chars/4 heuristic.** Anthropic instructs recounting per model (Claude 4.7+
   tokenizer produces ~30% more tokens).
8. **Thresholds to cite:** under 10 tools don't bother; 10-20 worth it; 30-50+ accuracy degrades.

### Open decisions for the skill author

1. **Depend on undocumented `claude -p "/context"`?** It works and is free, but is absent from the
   headless page's list of `-p`-capable built-in commands and from its `commands` row's availability
   note. Probe-and-degrade rather than hard-depend.
2. **Does deferral actually save billed tokens?** Gap 1 in the fetch log. Two `count_tokens` calls
   would settle it and would decide whether the skill reports deferral as a saving at all.
3. **Which key to recommend for persistence.** `permissions.deny` persists in settings.json;
   `disallowedTools` is not a settings.json key. Do not emit `disabledTools` — it is undocumented and
   the two issues requesting it were closed as not planned.
4. **Model-conditional baselines.** Claude Code already drops the Task tools on newer models to save
   context, so a baseline captured on one model does not transfer. Decide whether the skill records
   the model with each baseline.

### Verification status

`verification: pending`. Outcome-gate criteria 4 (≥2 independent corroborators per claim) and 7 (all
accepted claims HIGH confidence) are **not graded by this run** — the run made the source choices, so
it may not grade their independence. The evidence a verifier needs is in each sidecar's `sources[]`
header (url + tier + publishing pool) and in `RESEARCH-fetch-log.md`, which includes an explicit note
that first-party sources across `code.claude.com` and `platform.claude.com` share one publishing pool
and names which claims rest on Tier-0 local measurement instead. Project fit against this repo's
conventions is the parent's to apply.
