---
name: research
description: "Multi-source external research in three chained phases — broad, targeted + falsification, preferred sources — with per-claim source tiers, recency checks, and a binary outcome gate before presenting. Use to verify a technical claim, evaluate libraries or approaches, compare X vs Y, or ground any decision in current authoritative sources instead of training data."
argument-hint: "[topic] (e.g., /discovery:research <library> <version> best practices, /discovery:research <framework> hook event schema, /discovery:research <ORM> query optimization)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

External research is mandatory before acting on external facts. Goal: **maximum knowledge, maximum consensus, latest information** from authoritative + official sources. Training data drifts; library APIs change; SEO content farms outrank authoritative sources; AI synthesis tools repackage the same secondary blogs as "multi-source." Cross-tool consensus + primary-source priority + recency verification drive accuracy.

Local counterpart: `/explore` (what IS in the repo). This skill covers what SHOULD BE, per current external sources. For context-heavy passes, use `/research-deep` (dispatches to an isolated execution tier; keeps main context clean).

**Philosophy**: more tokens + more time = more accuracy + less rework. Insufficient research is the #1 source of rework. Deploy a **research team**, not a single lookup. Every invocation gets full depth regardless of task size.

## Topic

Research the following topic: $ARGUMENTS

If no specific topic was provided above, infer the research topic from the current conversation context — identify the technical claim, decision, or implementation being worked on and research that.

## Mandatory disciplines (non-negotiable)

Full recipes and rationale: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md` (also the canonical source-tier table for this plugin).

1. **3 phases minimum** — Phase 1 (broad), Phase 2 (targeted, informed by Phase 1, includes falsification), Phase 3 (preferred-sources / tool-ecosystem fallback)
2. **Queries scale to open questions — the floor is a starting point, not a target** — Phase 1 opens with ≥3 queries to seed the evidence base; Phase 2 and Phase 3 each run **one query per unresolved gap/conflict** surfaced by the prior phase's written analysis (≥3, no upper cap). Stopping at the floor while gaps remain is a violation — read every floor below as "at least," never "exactly"
3. **3 distinct tool types minimum per phase** — using only one search engine + one synthesis tool for a phase is a violation; mix in direct fetches, doc-MCP servers, `gh api`, or documentation agents your environment provides
4. **4+ distinct tool types across the topic** — phases cannot share the same 3 tools end-to-end. Cross-phase tool diversity is the consensus-driving mechanism
5. **Source-tier ratio per claim** — every accepted claim has ≥1 Tier 0/1 (primary source captured this turn) PLUS ≥2 independent corroborators, REGARDLESS of how authoritative the primary is: a canonical doc does not waive corroboration (it can be stale). Three synthesis-tool citations of three blogs = 1 Tier 2 source, NOT 3. Track diversity per claim
6. **Recency gate — first-party docs lag releases** — one query MUST fetch the LATEST upstream changelog or release notes this turn and confirm the claims are current as of it. The 30/14/90-day windows (standard / very active / conceptual) bound how stale a cited doc may be before it needs that cross-check — a stable project whose latest release is older than the window still passes once that release is confirmed current. Major version bump = invalidate prior docs INCLUDING first-party: treat any doc-vs-changelog lag as a conflict to resolve, not a closed answer
7. **One falsification query in Phase 2 (MANDATORY)** — Phase 2 must include exactly one query that attempts to FALSIFY the leading hypothesis from Phase 1
8. **Broad-topic auto-detect → doubled minimums** — when the topic involves 2+ vendors / 2+ tools / 3+ proper-noun products / comparison ("X vs Y") / migration ("X replaces Y") → 6+ queries per phase, 12+ total, 5+ tool types, 4+ Tier 0/1 sources per claim
9. **Phases chain through a WRITTEN analysis** — Phase 2 consumes the gap/conflict/leading-hypothesis list emitted at the end of Phase 1; each Phase 2 query maps to a named entry in it. Phase 3 chains the same way off the Phase 1+2 list. A query not traceable to a prior-phase gap is unchained — the written list IS the broad→deep link, intent is not
10. **Task size does NOT reduce phase count** — a one-line config change gets the same treatment as a multi-file feature
11. **Confidence tracked per claim** — HIGH / MEDIUM / LOW per the discipline file's "Confidence calibration." Do NOT accept LOW-confidence claims as a basis for code edits — iterate until HIGH
12. **Primary source fetched directly, not via the SERP** — for every accepted claim, name the canonical doc home and fetch it directly with whatever direct-fetch tool is connected this session, top-down through the discipline file's artifact ladder (an announcement page is not the vendor's deepest artifact); SERP + synthesis tools only DISCOVER what to fetch and find corroborators, never serve as the terminal source
13. **Outcome gate before presenting (MANDATORY)** — the run self-checks its own evidence table + written gap lists + fetch log against binary criteria; any FAIL returns to the named phase (see "Outcome gate")

## Phase 1: Broad Research (3+ queries, 3+ tool types)

Cast a wide net. Objective: establish the initial evidence base and identify what we don't know yet — survey the landscape before spending depth on any single source.

### Discover your tools first — don't assume a fixed set

Research tools vary by session: MCP servers connect and disconnect, CLIs come and go. Before launching, take stock of what's actually available THIS session — your active/deferred tool list, the MCP server-instruction blocks already injected into context, and the project's MCP registry. Map the source CATEGORIES below to whatever you have; never hard-depend on one server (a docs-MCP server absent → WebFetch the docs site directly instead).

**Launch ≥3 queries across ≥3 source categories in parallel:**

| Source category | What it gives you | Reach for whatever's connected |
|---|---|---|
| **Official docs** | The authoritative primary for an ecosystem/library | the ecosystem's canonical docs site, fetched directly. If the consuming project ships a per-ecosystem source mapping (check its `CLAUDE.md`/rules), use it; else identify the canonical home yourself. When the topic centers on a specific library/site, probe its `llms.txt` / sitemap first to enumerate the doc set |
| **Upstream source + releases** | Ground truth + recency for a tool/library | the GitHub repo, releases, `CHANGELOG.md` — required for the recency gate |
| **Package registry** | Versions, dependencies, publish dates | the ecosystem's registry (NuGet / PyPI / npm / crates.io / Maven Central) |
| **Spec / standard** | Definitive behavior for a protocol/language | the RFC, language spec, or standard document |
| **AI-synthesis — DISCOVERY ONLY** | Fast breadth + citations to chase | a synthesis tool to FIND primaries and corroborators — never the terminal source for a claim. When it exposes a depth/quality knob, max it (accuracy over speed) |
| **Community corroborators** | Independent agreement / dissent | named-author blogs, top-voted Q&A, practitioner posts — corroborators, not primaries |

- **Prefer direct-context web** (WebSearch / WebFetch in the main session) for the highest-value queries — results land without summarization loss.
- **Vendor-tool topics** — when the topic is the AI coding tool itself (or any fast-moving vendor tool), prefer a dedicated documentation agent/skill if your environment provides one; general synthesis tools carry stale info for fast-moving tools. Also check the upstream issue tracker for known bugs in the version in use.

### Phase 1 output — write this list before composing any Phase 2 query

**STOP. Emit a written analysis block** — this IS the broad→deep chaining mechanism. Phase 2 queries are composed FROM it, not alongside it. The block MUST contain:

- **Leading hypothesis** — what the evidence points toward
- **Gaps** (numbered) — each claim not yet backed by ≥1 primary (Tier 0/1) + 2 independent corroborators, plus any open question. Every numbered gap earns a Phase 2 query — the gap count sets the Phase 2 query count
- **Conflicts** (numbered) — disagreements between sources; each earns a resolving Phase 2 query
- **Tool-diversity audit** — distinct tool types used; if <3, this phase failed — re-run before proceeding
- **Recency status** — upstream changelog/release fetched? If not, queue for Phase 2
- **Falsification candidate** — the most load-bearing claim that, if wrong, invalidates the rest. That's the Phase 2 falsification target

Phase 2 is not "launch 3 queries" — it is "close every numbered gap + conflict above, plus the one falsification query." If that totals 6, run 6.

## Phase 2: Targeted + Falsification (one query per Phase 1 gap/conflict + 1 mandatory falsification)

Objective: fill gaps, resolve conflicts, strengthen low-confidence claims, AND attempt to break the leading hypothesis.

**One query MUST be a falsification attempt** against the Phase 1 leading hypothesis. See the discipline file's "Falsification step" for query patterns. Without this step, Phase 2 is confirmation bias by default.

**Remaining queries — one per numbered gap/conflict from the Phase 1 list:**

- **Gap-filling** — one query per numbered Phase 1 gap
- **Conflict resolution** — queries that specifically test contradicting claims with version-specific terms
- **Primary-source deep dives** — fetch the primary directly (raw release notes / docs pages) for claims needing Tier 1 confirmation
- **Recency verification** — if not done in Phase 1, fetch the upstream changelog/releases NOW

### Phase 2 output (before proceeding to Phase 3)

**STOP and analyze Phase 1+2 combined results.** Update the gap/conflict list. Identify Phase 3 sources (preferred-source authors OR the tool-ecosystem fallback if no author covers the domain).

## Phase 3: Preferred Sources OR Tool-Ecosystem Fallback (3+ queries)

Objective: cross-reference findings against trusted thought leaders OR upstream maintainers.

**Path A — a preferred-source roster exists.** If the consuming project maintains a preferred-sources roster (a list of trusted authors/domains in its `CLAUDE.md`, rules, or docs), identify 3+ entries relevant to the topic and launch 3+ queries using those author names as search qualifiers.

**Path B — no roster, or no listed author covers the domain (typical for tool-ecosystem topics).** MUST cite all three:

1. **Official maintainer** — the vendor's own social / GitHub / blog
2. **Upstream repo changelog or releases** — `gh api repos/<owner>/<repo>/releases` OR a raw `CHANGELOG.md` fetch this turn
3. **One recognized industry authority** — a top-voted community post or named-author practitioner blog

See the discipline file's "Tool-ecosystem Phase 3 fallback" for the playbook.

## Phase 4 (conditional): Additional follow-up

If Phases 1-3 still have gaps, conflicts, or LOW-confidence claims:

- Launch targeted queries to reach HIGH confidence on every remaining claim
- No limit on additional phases — iterate until every claim has HIGH confidence per the discipline file's "Confidence calibration"
- Regularly self-critique your approach and plan

## Research principles (apply throughout all phases)

- **Authoritative sources first** — Tier 0 (direct tool output) > Tier 1 (official docs fetched this turn) > Tier 2 (recognized authors, vetted blogs) > Tier 3 (training-data recall — NOT acceptable; must promote before acting). Tier table: the discipline file
- **Source code as spec** — when the topic is "how does library/implementation X behave" and X's source is reachable (GitHub, vendored dependency, package cache), READ the source — it outranks every doc about it, even across languages. For port/reimplementation topics, RESEARCH.md carries a semantics map: matched code excerpts (source ↔ target), gotcha notes, edge-case table
- **Version-aware** — always include version numbers in searches
- **Avoid SEO content farms** — down-rank listicles, repackaged content, vendor marketing pages. See the discipline file's "Source-quality red flags"
- **Main-context vs. agent trade-off** — prefer direct research when results inform decisions (avoids summarization loss). Use agents for parallel breadth within a phase
- **No shortcuts for small tasks** — a "quick config change" still gets the full discipline
- **No parallel MCP calls to the same stdio server** — that transport is serial. Run sequentially within a server, parallelize across different servers/tools
- **Graceful degradation** — if a tool category is unavailable this session, substitute equivalent coverage and document the gap; don't lower the bar

## Outcome gate (run before presenting — MANDATORY)

Research is not done when the phases finish — it's done when it passes this gate. Check what the run ACHIEVED against what good research requires, **grounded in the run's own artifacts** (the evidence table, the Phase 1/2 written gap lists, the fetch log) — NOT in your recollection of "did I do a good job." The same model that satisficed the bars runs this check, so a self-congratulatory recap rubber-stamps shallow work. Only artifact-grounded binary criteria bite.

Each criterion is binary — read it off an artifact, not from memory. **Any FAIL returns to the named phase; do not present until all pass:**

| # | Binary criterion | FAIL → |
|---|---|---|
| 1 | Every claim row has ≥1 Tier 0/1 source whose URL/command was captured THIS turn | Phase 2 — fetch the primary directly |
| 2 | No claim row's sources are ALL Tier-2 secondary | Phase 2 — get a primary |
| 3 | Every Phase 2/3 query traces to a numbered gap/conflict in a written analysis block | re-run the phase chained to the list |
| 4 | Every claim has ≥2 INDEPENDENT corroborators (not 2 cites of one upstream pool) | Phase 2 — widen sources |
| 5 | The Phase 2 falsification query ran and is recorded | Phase 2 — run it |
| 6 | Recency gate satisfied for every tool/library/API claim: the LATEST upstream changelog/release was fetched THIS turn and cross-checked against the claim (a stable project whose latest release is older than the 30/14/90d window passes once that release is confirmed as current; a major version bump since the cited doc invalidates it, first-party docs included) | Phase 2 — fetch changelog |
| 7 | Every accepted claim is HIGH confidence | Phase 4 follow-up — iterate to HIGH |
| 8 | Project fit checked against the consuming project's own conventions and stated direction | revisit before presenting |
| 9 | For every ACCEPTED claim taken from a publisher's own artifacts — vendor, OSS maintainer, and standards body alike — the fetch log ACCOUNTS FOR every rung of the artifact ladder above the one the claim came from: each is recorded as probed-and-lacking-the-claim, or as existing-but-unreachable after the escalation ladder and carried as an enumerated Gap. A recorded probe is not a licence to source from a shallower rung — a rung that exists, is reachable, and carries the claim IS where the claim comes from | Phase 2 — walk the ladder from rung 1, recording each probe and its result |
| 10 | Every reported absence names both the sources checked and the sources left unchecked — no bare "unsourced" / "not found" | revisit before presenting |

**Authoritative + consensus, reconciled:** the primary source is the SPINE of each claim; independent corroborators are the CONFIRMATION. When a top-ranked blog consensus contradicts the primary, the primary wins and the conflict is flagged explicitly — consensus never overrides a fetched authoritative source. Subagent returns are Tier 3 (synthesis), not corroborators, until their cited primaries are fetched this turn.

Zero tolerance for false positives. A claim that can't pass the gate is a **Gap**, not a finding — report it as such, never launder it into the answer. Report the gate result (pass, or which criterion failed + what you re-ran). No limit on iterations.

## Output Format

Present research findings as:

1. **Summary** — 2-3 sentence answer to the research question
2. **Evidence table** — `Claim | Sources (Tier 0/1 entries cite the URL/command fetched THIS turn) | Tier | Tool diversity | Confidence`
3. **Fetch log** — the written record criteria 6 and 9 are graded against, so it is WRITTEN, not recalled. One entry per fetch PER CLAIM: `Claim | URL or command | artifact-ladder rung | tool used | outcome`. The claim key is not decoration — criterion 9 is evaluated per accepted claim, and one artifact routinely carries claim A while lacking claim B, so an unkeyed outcome cannot show which claim it answers. Each accepted claim carries the entry for the rung it came from AND one for every rung ABOVE it, whose outcome states which of the three it was — carries the claim, does not carry it, or unreachable after escalation (which is also a Gap row). The changelog rung is required on top of that walk, not by it: criterion 6's cross-check is unconditional at every rung, so a claim sourced from a rung above the changelog still carries its own latest-release/changelog entry — without it the recency gate is graded from recollection, which is exactly what this log exists to prevent
4. **Conflicts** — disagreements between sources (flagged explicitly; primary wins over blog consensus)
5. **Gaps** — claims not at ≥1 primary + 2 independent corroborators, OR LOW confidence (flagged for follow-up). A gap asserting absence names the sources checked AND the sources left unchecked — never a bare "not found"
6. **Recency status** — primary-source age per tool/library claim
7. **Project fit** — how findings align with the consuming project's conventions and stated direction
8. **Outcome gate result** — pass, or which criterion failed and what was re-run

If invoked standalone, present findings directly. If invoked as part of a larger workflow, findings feed into the subsequent planning step.

## Final step: persist artifact for handoff

Write the research output to `<memory_dir>/<slug>/RESEARCH.md` — a memory-tier artifact, never committed. Destination, slug, and runtime guards resolve per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).

This file is the authoritative summary of the stage — a fresh session must be able to resume planning reading only this artifact.

The artifact opens with a Task restatement, follows the Output Format above, and closes with a Next-stage-handoff (settled facts vs. open decisions for the planning step).

If research spans many topics and RESEARCH.md exceeds ~2000 words, split overflow into sibling `RESEARCH-<topic>.md` files in the same directory and keep RESEARCH.md as the index.

**Intra-task pivot — delete stale research, don't layer.** If the approach you researched is abandoned mid-task for a different direction *before shipping*, delete the now-stale RESEARCH.md section and re-run the research on the new direction rather than keeping both — a superseded section misleads the planning step into planning against a dead approach.

## What this skill does NOT do

- **Does not make decisions** — presents verified evidence; the planning step (or user) decides
- **Does not write code** — researches only; execution is a separate step
- **Does not skip phases for "simple" topics** — task size does NOT reduce depth. All phases always run
- **Does not present training-data knowledge as current fact** — Tier 3 recall must be promoted to Tier 0/1 before claim acceptance

## See also

- `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md` — source tiers, recency gates, broad-topic recipe, falsification recipe, tool-ecosystem fallback, confidence calibration, source-quality red flags, observed failure patterns
