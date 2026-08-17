---
topic: plugins-mcp-context-budget
section: methodology
abstract: Fetch log, artifact-ladder walk, conflicts, recency verdict and outcome-gate result for the plugins/MCP context-budget research run.
claims:
  - claim: "The recency gate is satisfied: latest upstream release is 2.1.233 (2026-08-14), confirmed from two independent hosts this turn, against an installed 2.1.232; no major version bump, so no doc invalidation."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/changelog (top entry: Update label 2.1.233, August 14, 2026)"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (top entry: ## 2.1.233)"
        tier: 1
        pool: "anthropics/claude-code GitHub repository"
      - url: "claude --version → 2.1.232 (Claude Code)"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
produced_by: phase-0-through-4
---

# Methodology, fetch log, conflicts and gate result

Run date **2026-08-17**. Budget: full depth, official-docs-first. Nesting unavailable, so all phases
ran sequentially in this context; no sub-delegation.

## Preload liveness

The `discovery:research` skill body was **NOT** preloaded into this context — the sentinel
`discovery-research-preload-4c1f9a` was absent on arrival. Per the researcher contract's fallback I
read `plugins/discovery/skills/research/SKILL.md` and its `context/discipline.md`,
`context/artifact-shape.md`, `context/source-categories.md` directly before any query, and ran the
discipline from those. The token is echoed in the return payload from the file I read, not from a
preload.

## Corpus enumeration (Phase 0)

Verdict: **BOUNDED**. Enumerated from three surfaces exhaustive by construction —
`https://code.claude.com/docs/sitemap.xml` (187 `/docs/en/` pages), `claude --help` plus each
relevant subcommand's `--help` (v2.1.232), and the release stream. Ledger written to
`research-checklist.md` before the first query, with narrowing recorded in its header. `llms.txt`
exists at `/docs/llms.txt` (200) but is curated, so it was used for prioritisation only, never for
completeness.

## Tool diversity

Seven distinct tool types across the run, five of them in Phase 1:

| Tool type | Used for |
|---|---|
| `curl` direct fetch of `.md` page variants | Verbatim primary text (the `.md` variant probe returned 200 on every page tried) |
| Bash Tier-0 CLI invocation | `claude --help`, `claude plugin *`, `claude mcp *`, `claude plugin details`, `claude --version` |
| Bash Tier-0 headless probes | `claude -p "<slash command>"` × 9 |
| Binary extraction (`grep -abo` + `dd` + Python decode) | The `/doctor` bundled-skill prompt |
| `WebFetch` | `debug-your-config`, GitHub issue #40314 |
| `WebSearch` | Falsification + Phase 3 community corroborators |
| GitHub MCP (`mcp__github__list_releases`) | Attempted; **access denied** — session is scoped to `melodic-software/claude-code-plugins` only. Substituted with a raw `CHANGELOG.md` fetch (documented degradation) |

## Artifact-ladder walk

Ladder rungs per `discipline.md`. For every accepted claim class:

| Rung | Artifact for this topic | Outcome |
|---|---|---|
| 1 — deepest technical artifact | The shipped `/doctor` skill prompt inside the `claude` binary; `claude plugin details` output; live `/context` output | **carries the claim** for Q2, Q5, Q6 |
| 2 — platform/API reference | `docs/en/settings`, `docs/en/plugins-reference`, `docs/en/mcp`, `docs/en/commands` | **carries the claim** for Q1, Q3, Q6 |
| 3 — product docs | `docs/en/plugins`, `docs/en/skills`, `docs/en/prompt-caching`, `docs/en/debug-your-config`, `docs/en/costs` | **carries the claim** for Q4, Q5 |
| 4 — changelog / releases | `docs/en/changelog` and `raw.githubusercontent.com/.../CHANGELOG.md` | **carries the claim** for Q5's version, and serves the recency cross-check |
| 5 — announcement | `docs/en/whats-new/2026-w28` | fetched and searched via WebSearch surfacing only; not used as a terminal source |
| 6 — third-party | Substack/DEV/aggregator posts | corroborators only; several rejected on source-quality grounds |

**Rung 1 exists for this topic and was reached**, which is unusual and is what makes Q2 and Q5
HIGH-confidence rather than doc-only: the product's own shipped prompt and its own token-counting
command are the deepest artifacts, and both were read directly rather than described.

## Fetch log

`Claim | URL or command | rung | tool | outcome`

| Claim | URL / command | Rung | Tool | Outcome |
|---|---|---|---|---|
| Q1 `enabledPlugins` spelling + scopes | `https://code.claude.com/docs/en/settings.md` | 2 | curl | carries the claim |
| Q1 precedence order | same | 2 | curl | carries the claim |
| Q1 installation scopes incl. managed | `https://code.claude.com/docs/en/plugins-reference.md` | 2 | curl | carries the claim |
| Q1 settable scopes | `claude plugin enable/disable --help` | 1 | Bash | carries the claim |
| Q1 on-disk key shape | read of `~/.claude/settings.json` keys | 1 | Bash/python | carries the claim |
| Q1 `defaultEnabled` fallback | `https://code.claude.com/docs/en/plugins-reference.md` | 2 | curl | carries the claim |
| Q1 deep-merge across scopes | `settings.md`, `plugins-reference.md`, `plugin-dependencies.md`, `plugin-marketplaces.md` | 2 | curl | **fetched and searched, does not carry the claim** → recorded as a Gap |
| Q1 recency | `docs/en/changelog` + raw `CHANGELOG.md` | 4 | curl | 2.1.233 (2026-08-14) — current |
| Q2 component inventory + cost columns | `https://code.claude.com/docs/en/plugins-reference.md` | 2 | curl | carries the claim |
| Q2 measured per-plugin cost | `claude plugin details actionlint@melodic-software` | 1 | Bash | carries the claim |
| Q2 hooks harness-only | same command output | 1 | Bash | carries the claim |
| Q2 skill listing budget | `https://code.claude.com/docs/en/skills.md` + `settings.md` | 2/3 | curl | carries the claim |
| Q2 agents always-loaded | `claude -p "/context"` | 1 | Bash | carries the claim |
| Q2 LSP context cost | `plugins-reference.md`, `discover-plugins.md`, `costs.md`, `context-window.md`, `plugin details`, `/doctor` prompt | 1–3 | curl/Bash | **fetched and searched, does not carry the claim** → Gap |
| Q2 output styles load timing | `https://code.claude.com/docs/en/output-styles.md` | 3 | curl | carries the claim |
| Q2 recency | `docs/en/changelog` + raw `CHANGELOG.md` | 4 | curl | 2.1.233 (2026-08-14) — current |
| Q3 `*Mcpjson*` key spellings | `https://code.claude.com/docs/en/settings.md` | 2 | curl | carries the claim |
| Q3 the two disjoint key pairs | `https://code.claude.com/docs/en/mcp.md` | 2 | curl | carries the claim |
| Q3 disable mechanics | binary-extracted `/doctor` prompt | 1 | Bash/dd | carries the claim |
| Q3 MCP scope precedence | `https://code.claude.com/docs/en/mcp.md` | 2 | curl | carries the claim |
| Q3 `claude mcp add` scope default | `claude mcp add --help` | 1 | Bash | carries the claim |
| Q3 deferral default + `ENABLE_TOOL_SEARCH` matrix | `https://code.claude.com/docs/en/mcp.md` | 2 | curl | carries the claim |
| Q3 `alwaysLoad` | `mcp.md` + raw `CHANGELOG.md` | 2/4 | curl | carries the claim |
| Q3 deferral corroboration | `https://code.claude.com/docs/en/costs.md` | 3 | curl | carries the claim |
| Q3 live deferral evidence | `claude -p "/context"` (`System tools (deferred)` row) | 1 | Bash | carries the claim |
| Q3 **falsification** | `https://github.com/anthropics/claude-code/issues/40314` | 6 | WebFetch | carries counter-evidence — see Conflicts |
| Q3 recency | `docs/en/changelog` + raw `CHANGELOG.md` | 4 | curl | 2.1.233 (2026-08-14) — current |
| Q4 invalidation list | `https://code.claude.com/docs/en/prompt-caching.md` | 3 | curl | carries the claim |
| Q4 plugin section verbatim | same | 3 | curl | carries the claim |
| Q4 `/reload-plugins --force` gate | `https://code.claude.com/docs/en/commands.md` | 2 | curl | carries the claim |
| Q4 cache lifetime TTL | `prompt-caching.md` | 3 | curl | **unresolved** — section present, not extracted → Gap |
| Q4 recency | `docs/en/changelog` + raw `CHANGELOG.md` | 4 | curl | 2.1.233 (2026-08-14) — current |
| Q5 `/doctor` is a bundled skill | `https://code.claude.com/docs/en/commands.md` + `skills.md` | 2/3 | curl | carries the claim |
| Q5 registration flags | binary strings (`survivesBundledKillSwitch`, `disableModelInvocation`) | 1 | Bash | carries the claim |
| Q5 full check list + Check 1 + Check 6 | binary-extracted `/doctor` prompt | 1 | Bash/dd | carries the claim |
| Q5 version 2.1.205 | `docs/en/changelog` + `debug-your-config.md` + raw `CHANGELOG.md` | 4/3 | curl | carries the claim |
| Q5 community corroboration | WebSearch results (Substack/DEV) | 6 | WebSearch | corroborator; aggregators rejected |
| Q5 recency | `docs/en/changelog` + raw `CHANGELOG.md` | 4 | curl | 2.1.233 (2026-08-14) — current |
| Q6 headless matrix | `claude -p "<cmd>"` × 9 | 1 | Bash | carries the claim |
| Q6 command descriptions | `https://code.claude.com/docs/en/commands.md` | 2 | curl | carries the claim |
| Q6 `/doctor` command table row | same | 2 | curl | carries the claim |
| Q6 `--safe-mode` / `--bare` / `--setting-sources` | `claude --help` (v2.1.232) | 1 | Bash | carries the claim |
| Q6 safe-mode managed nuance | `https://code.claude.com/docs/en/debug-your-config` | 3 | WebFetch | carries the claim |
| Q6 `CLAUDE_CONFIG_DIR` | `https://code.claude.com/docs/en/env-vars.md` | 2 | curl | carries the claim |
| Q6 `/usage` attribution | `https://code.claude.com/docs/en/costs.md` | 3 | curl | carries the claim |
| Q6 interactive-only under other output formats | not attempted | 1 | — | **unresolved** → Gap |
| Q6 recency | `docs/en/changelog` + raw `CHANGELOG.md` | 4 | curl | 2.1.233 (2026-08-14) — current |

## Conflicts

1. **Deferral by default vs. observed non-deferral of HTTP MCP tools.** The docs, the changelog and
   live `/context` all say MCP tools are deferred by default. Issue #40314 (v2.1.86, **closed as not
   planned**) reports HTTP/Streamable-HTTP MCP tools loading 120K tokens upfront despite
   `ENABLE_TOOL_SEARCH=auto:5`. **Primary wins on the default**; the issue is recorded as a
   transport-specific caveat, and the practical resolution is that the skill must *measure* deferral
   via `/context` rather than assume it. Unresolved whether it is fixed by 2.1.23x.

2. **Third-party claim that plugin hooks/agents cost context every turn.** An aggregator page
   surfaced in Phase 3 asserts an active plugin's "skills, agents, hooks, and above all its MCP
   servers weigh on your context window turn after turn". This **contradicts the primary** twice:
   `claude plugin details` annotates hooks "harness-only — no model context cost", and MCP tools are
   deferred. Primary wins; the third-party source is not cited as a corroborator.

3. **`/doctor` "unused extensions" wording.** `debug-your-config` says "unused extensions" while
   `commands` says "unused skills, MCP servers, and plugins" and the shipped prompt says the latter.
   Not a substantive conflict — the shipped prompt is authoritative and more specific.

## Source-quality red flags recorded

Phase 3 search surfaced several unattributed aggregator/SEO domains (wmedia.es, mcp.directory,
computingforgeeks, and a "cheat sheet" listicle). Per the discipline's red-flag list these were
down-ranked and **not** used as corroborators for any accepted claim. No prompt-injection attempts
were observed in any fetched page.

## Recency status

| Subject | Latest confirmed | Verdict |
|---|---|---|
| Claude Code | **2.1.233**, published 2026-08-14, confirmed this turn from two independent hosts | **current** — 3 days old, inside the 14-day window for a very active project |
| Installed build under test | 2.1.232 (2026-08-13) | one release behind the docs; no behaviour claim in this artifact depends on a 2.1.233 change |

No major version bump (2.x throughout), so no prior-doc invalidation applies.

## Graceful degradation

The GitHub MCP server is scoped to `melodic-software/claude-code-plugins` and denied
`anthropics/claude-code`; `gh` is not installed. Equivalent coverage was obtained by fetching
`raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` directly (Tier 1, different host
from `code.claude.com`, so it is an independent corroborator of the release stream). Residual risk:
I could not read issue metadata (labels, linked PRs, close reason beyond the WebFetch summary) for
issue #40314, which is why its fix status is a Gap rather than a finding.

## Gaps (claims NOT accepted)

Each is stated in its own sidecar's "What I could NOT verify" section. Consolidated:

1. Whether `enabledPlugins` deep-merges across scopes or is replaced whole (Q1).
2. Whether plugin-provided **LSP servers** carry any always-loaded model-context cost (Q2).
3. Whether a **plugin can ship an output style** (Q2) — `plugins-reference`'s component list omits
   it; `--safe-mode` help groups it with plugin-adjacent customizations.
4. Whether issue #40314's HTTP-transport deferral failure is fixed as of 2.1.232/2.1.233 (Q3).
5. Whether `alwaysLoad` is settable on a plugin-provided server's `.mcp.json` (Q3).
6. The prompt cache **TTL / lifetime** value (Q4).
7. Whether the internal "skill" classification of `/doctor` landed exactly on 2.1.205 or later (Q5).
8. Whether the six interactive-only commands behave differently under `--output-format stream-json`,
   in a TTY, or outside a nested Claude Code session (Q6).
9. Whether `/usage` runs headlessly (Q6).
10. Whether `claude --safe-mode -p "/context"` / `--bare -p "/context"` yields a usable floor
    measurement (Q6) — designed, not executed.

Every absence above names the sources checked and the sources left unchecked in its home sidecar.

## Project fit

**Not assessed — this is the parent's row.** This artifact does not judge fit against the consuming
repository's conventions; that criterion belongs to the dispatching context, which holds them.

## Outcome gate result

| # | Criterion | Owner | Result |
|---|---|---|---|
| 1 | Every claim row has ≥1 Tier 0/1 source captured this turn | run | **PASS** |
| 2 | No claim row is all-Tier-2 | run | **PASS** — no accepted claim rests on a secondary source |
| 3 | Every Phase 2/3 query traces to a numbered gap/conflict | run | **PASS** |
| 4 | ≥2 independent corroborators per claim | **verifier** | not self-graded; `sources[]` with `pool` supplied in every sidecar header |
| 5 | Falsification query ran and is recorded | run | **PASS** — targeted deferral-by-default; found real counter-evidence (#40314), recorded as Conflict 1 |
| 6 | Recency gate satisfied | run | **PASS** — 2.1.233 (2026-08-14) confirmed from two hosts; verdict `current` |
| 7 | Every accepted claim HIGH confidence | **verifier** | not self-graded |
| 8 | Project fit | **parent** | not assessed — parent's row |
| 9 | Artifact ladder accounted for above the sourcing rung | run | **PASS** — walk table above; rung 1 reached and carries the claim for Q2/Q5/Q6 |
| 10 | Every reported absence names checked and unchecked sources | run | **PASS** — see Gaps and each sidecar |
| 11 | Coverage ledger fully marked | run, **script verdict** | see the exit status cited in the index |

**Caveat on independence for criterion 4:** most Tier-1 corroboration here comes from
`code.claude.com`, which is a **single publishing pool** however many pages are cited. Genuine
independence in this run comes from: (a) the installed binary and CLI output (Tier 0, a different
artifact class from the docs), (b) `raw.githubusercontent.com/anthropics/claude-code` (different
host, different artifact), and (c) live `/context` measurement. The verifier should weigh
multi-page `code.claude.com` citations as **one** pool.
