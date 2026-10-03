# Research phases

Load this file when you are the worker, before the first query. `SKILL.md` keeps the routing
gates, the discipline list, and the outcome-gate table. This file is Phase 0 through Phase 4.

## Phase 0: Corpus enumeration (before any query)

**Ask first: is the corpus bounded?** Bounded means finite and enumerable *before* the first query. Every skill in a plugin, every endpoint in an API reference, every release between two versions. An unbounded topic ("is this approach sound?") has no such set; record that verdict in one line and go to Phase 1. When it IS bounded, **enumerate from a surface that is exhaustive by construction**, never from search results or a curated index that is partial by design. Write `research-checklist.md` into the artifact's memory slice **in exactly this shape**. Criterion 11's gate parses it and fails closed on a table it cannot read, so a renamed column or a prose status is a FAIL:

```markdown
| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | <item>      | <what counts as covered for THIS item> | [ ] |
```

The last column is literally named `Done` and holds `[ ]` or `[x]`, not `Status`, not `DONE`, not prose. Each row carries a **per-item depth criterion fixed at enumeration time** ("its `frontmatter` section read end to end", not "researched"). Mark a row only when its own criterion is met. Narrowing is legitimate, quiet narrowing is not. Full recipe, why a criterion written afterwards drifts, and the exhaustive-surface table: the discipline file's "Corpus enumeration".

## Phase 1: Broad Research (3+ queries, 3+ tool types)

Cast a wide net. Objective: establish the initial evidence base and identify what we don't know yet. Survey the landscape before spending depth on any single source.

At `low` the skill's Effort table caps this phase and puts a named artifact or folder ahead of any web query.

**Launch ≥3 queries across ≥3 source categories in parallel**. Official docs, upstream source + releases, package registry, spec/standard, AI-synthesis (discovery only, never a terminal source), community corroborators. Take stock of what is actually connected THIS session and map the categories onto it; never hard-depend on one server. The category table, the two standing preferences, and why category diversity is the mechanism rather than a quota: [`source-categories.md`](source-categories.md).

### Phase 1 output. Write this list before composing any Phase 2 query

Write the analysis block before composing any Phase 2 query. Phase 2 queries are composed from it, which is what chains the broad pass to the deep one. The block contains:

- **Leading hypothesis**. What the evidence points toward
- **Gaps** (numbered). Each claim not yet at HIGH (criterion 7) or still below the criterion-4 floor of ≥1 primary (Tier 0/1) + 2 independent corroborators, plus any open question. Every numbered gap earns a Phase 2 query, the gap count sets the Phase 2 query count
- **Conflicts** (numbered). Disagreements between sources; each earns a resolving Phase 2 query
- **Tool-diversity audit**, distinct tool types used; if <3, this phase failed, re-run before proceeding
- **Recency status**. Upstream changelog/release fetched? If not, queue for Phase 2
- **Falsification candidate**, the most load-bearing claim that, if wrong, invalidates the rest. That's the Phase 2 falsification target

Phase 2 is not "launch 3 queries". It is "close every numbered gap + conflict above, plus the one falsification query." If that totals 6, run 6.

## Phase 2: Targeted + Falsification (one query per Phase 1 gap/conflict + 1 mandatory falsification)

Objective: fill gaps, resolve conflicts, strengthen low-confidence claims, AND attempt to break the leading hypothesis.

**One query is a falsification attempt** against the Phase 1 leading hypothesis. See the discipline file's "Falsification step" for query patterns. Without this step, Phase 2 is confirmation bias by default.

**Remaining queries. One per numbered gap/conflict from the Phase 1 list:**

- **Gap-filling**. One query per numbered Phase 1 gap
- **Conflict resolution**. Queries that specifically test contradicting claims with version-specific terms
- **Primary-source deep dives**. Fetch the primary directly (raw release notes / docs pages) for claims needing Tier 1 confirmation
- **Recency verification**, if not done in Phase 1, fetch the upstream changelog/releases NOW

**Fan out per gap when nesting is available.** When the dispatch prompt says `nested spawning available` and the Phase 1 list carries two or more numbered gaps, dispatch the gap queries to parallel workers in one turn, one per gap or per group of gaps that share a primary, and merge and confirm their fetches yourself; the falsification query stays yours. Without nesting, run the gaps one after another. Grouping, the worker brief, and the merge rule: the discipline file's "Per-gap fan-out (Phase 2)".

### Phase 2 output (before proceeding to Phase 3)

**Analyze the Phase 1 and Phase 2 results together before any Phase 3 query.** Update the gap/conflict list. Identify Phase 3 sources (preferred-source authors OR the tool-ecosystem fallback if no author covers the domain).

## Phase 3: Preferred Sources OR Tool-Ecosystem Fallback (3+ queries)

Objective: cross-reference findings against trusted thought leaders OR upstream maintainers.

**Path A, a preferred-source roster exists.** If the consuming project maintains one (trusted authors/domains in its `CLAUDE.md`, rules, or docs), identify 3+ relevant entries and launch 3+ queries using those author names as search qualifiers.

**Path B. No roster, or no listed author covers the domain (typical for tool-ecosystem topics).** Cite all three:

1. **Official maintainer**, the vendor's own social / GitHub / blog
2. **Upstream repo changelog or releases**. `gh api repos/<owner>/<repo>/releases` OR a raw `CHANGELOG.md` fetch this turn
3. **One recognized industry authority**, a top-voted community post or named-author practitioner blog

Tool-ecosystem Phase 3 fallback playbook: the discipline file's "Tool-ecosystem Phase 3 fallback".

## Phase 4 (conditional): Additional follow-up

If Phases 1-3 still have gaps, conflicts, or LOW-confidence claims, launch targeted queries until every claim reaches HIGH confidence per the discipline file's "Confidence calibration", or list it in the Gaps section with its MEDIUM or LOW label. There is no limit on additional phases. Self-critique the approach as you go.

## Research principles (apply throughout all phases)

- **Authoritative sources first**. Tier 0 (direct tool output) > Tier 1 (official docs fetched this turn) > Tier 2 (recognized authors, vetted blogs) > Tier 3 (training-data recall, NOT acceptable; must promote before acting). Tier table: the discipline file
- **Source code as spec**, when the topic is "how does library/implementation X behave" and X's source is reachable (GitHub, vendored dependency, package cache), READ the source: it outranks every doc about it, even across languages. Port/reimplementation topics carry a semantics map in `RESEARCH.md`. Matched excerpts (source ↔ target), gotcha notes, edge-case table
- **Version-aware**, always include version numbers in searches
- **Avoid SEO content farms**. Down-rank listicles, repackaged content, vendor marketing pages. See the discipline file's "Source-quality red flags"
- **Summarization loss is bounded by the artifact, not by staying inline**, the evidence table, fetch log and gap lists are on disk, so a consumer needing a detail reads it rather than re-running. Use parallel workers for breadth within a phase (Phase 2's per-gap fan-out is that step); never let one hand back a verdict whose primary it alone read
- **No parallel MCP calls to the same stdio server**. That transport is serial. Run sequentially within a server, parallelize across different servers/tools
- **Graceful degradation**, if a tool category is unavailable this session, substitute equivalent coverage and document the gap; don't lower the bar
