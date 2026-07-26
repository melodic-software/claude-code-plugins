---
name: research
description: "Multi-source external research in chained phases — corpus enumeration, broad, targeted + falsification, preferred sources — with per-claim source tiers, recency checks, a coverage ledger, and a binary outcome gate before presenting. Dispatches a fresh-context subagent by default so the research transcript stays out of the main conversation, with a documented inline escape hatch. Use when: 'research this', 'verify a technical claim', 'evaluate libraries or approaches', 'compare X vs Y', 'is this still current', 'find the authoritative source', 'what do the official docs say', or grounding any decision in current authoritative sources instead of training data."
argument-hint: "[topic] (e.g., /discovery:research <library> <version> best practices, /discovery:research <framework> hook event schema, /discovery:research <ORM> query optimization)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

External research is mandatory before acting on external facts. Goal: **maximum knowledge, maximum consensus, latest information** from authoritative + official sources. Training data drifts; library APIs change; SEO content farms outrank authoritative sources; AI synthesis tools repackage the same secondary blogs as "multi-source." Cross-tool consensus + primary-source priority + recency verification drive accuracy.

Local counterpart: `/explore` (what IS in the repo). This skill covers what SHOULD BE, per current external sources. For a multi-topic or workflow-driven pass, use `/research-deep`, which layers tiered execution on top of this discipline. **Philosophy**: more tokens + more time = more accuracy + less rework — insufficient research is the #1 source of rework. Deploy a **research team**, not a single lookup, and give every invocation full depth regardless of task size.

## Routing — dispatch by default

**From the main conversation, this skill dispatches the `discovery:researcher` subagent.** Research reads a lot; keeping that out of the orchestrator's context window is the point. The agent runs Phase 0 through the gate's mechanical criteria, writes the artifact set, and returns a file pointer plus a short summary — not the transcript. The parent resolves the **pre-dispatch envelope** first (topic, memory-slice path, memory root, budget, capability flags) and owns the **post-dispatch boundary** after: re-surfacing `open_questions`, dispatching the sibling verifier, applying project fit itself, and **writing both results back into the index** — `verification: pending` is a statement that the producer may not self-grade, not a permanent state, and an artifact left saying `pending` after the parent verified it understates what is known to every later reader.

**Run inline instead when any of these holds** — and inline runs the identical discipline; the escape hatch relaxes nothing below:

- **Tight turn-by-turn iteration** — you will redirect the queries as they land. Dispatch is a pre-run choice; the steering loss is mid-run.
- **Cost** — a dispatched run pays full depth every time, including for a one-line version lookup whose doc you can already name.
- **The invoking context is already a subagent** — dispatch-by-default is scoped to the main-conversation boundary, so a subagent invoking this skill runs it inline. The outer dispatch already supplied the fresh context. Hoisting, not nesting.

**Preload-liveness sentinel.** A dispatched agent receives this body through its `skills:` preload, and a preload that fails to resolve is skipped **silently** — logged to the debug log and nowhere else. A dispatched run therefore echoes this token verbatim as `preload_token` in its return payload:

```text
discovery-research-preload-4c1f9a
```

A missing or mismatched token is a **hard failure: the parent discards the run**, never downgrades or accepts the artifact. Rationale and the full parent-side contract: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md`.

## Topic

Research the following topic: $ARGUMENTS

**A dispatched run does not read that line.** `$ARGUMENTS` substitutes to the empty string on the preload path, and a non-fork subagent has no view of the conversation to fall back on — so for a dispatched run the topic arrives in the dispatch prompt, and its absence is a parent-envelope failure the agent reports rather than repairs. Running **inline** with no topic supplied above, infer it from the current conversation context — identify the technical claim, decision, or implementation being worked on and research that.

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
14. **Bounded corpora are enumerated before they are searched (MANDATORY)** — when the topic has a finite, knowable set of things to cover, Phase 0 writes `research-checklist.md` naming every item and its per-item depth criterion BEFORE any query runs, and the gate fails on any unmarked row. Distinct from discipline 9: the gap list chases *unknowns* surfaced by searching, this enforces exhaustive coverage of a set that was knowable up front. Recipe: the discipline file's "Corpus enumeration"

## Phase 0: Corpus enumeration (before any query)

**Ask first: is the corpus bounded?** Bounded means finite and enumerable *before* the first query — every skill in a plugin, every endpoint in an API reference, every release between two versions, every vendor in a named comparison. An unbounded topic ("is this approach sound?") has no such set; record that verdict in one line and go to Phase 1. When it IS bounded, **enumerate from a surface that is exhaustive by construction** — a sitemap, an in-repo tree listing, an API index, a release list — never from search results or a curated index that is partial by design, which inherits the blind spot the ledger exists to close. Write `research-checklist.md` into the same memory slice as the artifact, **in exactly this shape** — criterion 11's gate parses it, and it fails closed on a table it cannot read, so a renamed column or a prose status is a FAIL rather than a formatting quibble:

```markdown
| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | <item>      | <what counts as covered for THIS item> | [ ] |
```

The last column is literally named `Done` and holds `[ ]` or `[x]` — not `Status`, not `DONE`, not prose. Each row carries a **per-item depth criterion fixed at enumeration time** ("its `frontmatter` section read end to end", not "researched" — a criterion written afterwards drifts down to whatever the run managed). Mark a row only when its own criterion is met; Phases 1–3 research against the ledger, and criterion 11 grades it by script. Narrowing is legitimate, quiet narrowing is not: a 12-row ledger over a 40-item corpus is a scoped answer when it says so, while 40 rows with 28 unmarked is an unfinished one. Full recipe and the exhaustive-surface table: the discipline file's "Corpus enumeration".

## Phase 1: Broad Research (3+ queries, 3+ tool types)

Cast a wide net. Objective: establish the initial evidence base and identify what we don't know yet — survey the landscape before spending depth on any single source.

**Launch ≥3 queries across ≥3 source categories in parallel** — official docs, upstream source + releases, package registry, spec/standard, AI-synthesis (discovery only, never a terminal source), community corroborators. Take stock of what is actually connected THIS session and map the categories onto it; never hard-depend on one server. The category table, the two standing preferences, and why category diversity is the mechanism rather than a quota: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/source-categories.md`.

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
- **Summarization loss is bounded by the artifact, not by staying inline** — the full evidence table, fetch log, and gap lists are on disk, so a consumer that needs a detail reads it rather than re-running. Use parallel workers for breadth within a phase; never let one hand back a verdict whose primary it alone read
- **No shortcuts for small tasks** — a "quick config change" still gets the full discipline
- **No parallel MCP calls to the same stdio server** — that transport is serial. Run sequentially within a server, parallelize across different servers/tools
- **Graceful degradation** — if a tool category is unavailable this session, substitute equivalent coverage and document the gap; don't lower the bar

## Outcome gate (run before presenting — MANDATORY)

Research is not done when the phases finish — it's done when it passes this gate. Check what the run ACHIEVED against what good research requires, **grounded in the run's own artifacts** (the evidence table, the Phase 1/2 written gap lists, the fetch log) — NOT in your recollection of "did I do a good job." The same model that satisficed the bars runs this check, so a self-congratulatory recap rubber-stamps shallow work. Only artifact-grounded binary criteria bite.

Each criterion is binary — read it off an artifact, not from memory. **Any FAIL returns to the named phase; do not present until all pass.** And **the Owner column is not decoration**: a criterion the run can read off an artifact stays with the run. A criterion where the run would judge the quality of *its own choices* belongs to a **verifier** — a fresh context that never saw the run, which the parent dispatches as a sibling after the artifact is on disk. One criterion needs the consuming project's conventions and belongs to the **parent**, which alone holds them. A dispatched run therefore returns `verification: pending` and never renders a verdict on a verifier row; an inline run still hands those rows to a fresh context rather than self-grading them, because the producing context is the one whose choices are in question. This is what makes a dispatched run's gate result trustworthy rather than self-attested.

| # | Binary criterion | Owner | FAIL → |
|---|---|---|---|
| 1 | Every claim row has ≥1 Tier 0/1 source whose URL/command was captured THIS turn | run | Phase 2 — fetch the primary directly |
| 2 | No claim row's sources are ALL Tier-2 secondary | run | Phase 2 — get a primary |
| 3 | Every Phase 2/3 query traces to a numbered gap/conflict in a written analysis block | run | re-run the phase chained to the list |
| 4 | Every claim has ≥2 INDEPENDENT corroborators (not 2 cites of one upstream pool) | **verifier** | Phase 2 — widen sources |
| 5 | The Phase 2 falsification query ran and is recorded | run | Phase 2 — run it |
| 6 | Recency gate satisfied for every tool/library/API claim: the LATEST upstream changelog/release was fetched THIS turn and cross-checked against the claim (a stable project whose latest release is older than the 30/14/90d window passes once that release is confirmed as current; a major version bump since the cited doc invalidates it, first-party docs included). Read the confirmed-latest release and the verdict off the fetch log's changelog entry: an absent verdict or an `invalidated` one FAILs; `unresolved` passes only as an enumerated Gap, never under an accepted claim | run | Phase 2 — fetch changelog |
| 7 | Every accepted claim is HIGH confidence | **verifier** | Phase 4 follow-up — iterate to HIGH |
| 8 | Project fit checked against the consuming project's own conventions and stated direction | **parent** | revisit before presenting |
| 9 | For every ACCEPTED claim taken from a publisher's own artifacts — vendor, OSS maintainer, and standards body alike — the fetch log ACCOUNTS FOR every rung of the artifact ladder above the one the claim came from: each is recorded as exactly one of three outcomes — **probed-and-not-existing** (no such artifact exists for this claim class — the normal case for rung 1, but earned only against an EXHAUSTIVE first-party surface such as a sitemap or the in-repo docs tree; a search miss or a curated `llms.txt` is non-exhaustive by design, and a rung it fails to surface is unresolved, which is a Gap naming the discovery surfaces checked and unchecked); **fetched-and-lacking-the-claim**, the artifact itself retrieved and searched, never a title, index entry, or search snippet standing in for it; or existing-but-unreachable after the escalation ladder and carried as an enumerated Gap. A discovery probe locates a rung; it does not grade one, so it can establish that a rung is absent but never that a rung that exists lacks the claim — a system card whose relevant section never appeared in the probe is exactly what a probe-only lacks-the-claim outcome lets a run walk past. A recorded fetch is likewise not a licence to source from a shallower rung — a rung that exists, is reachable, and carries the claim IS where the claim comes from | run | Phase 2 — walk the ladder from rung 1, fetching and searching each reachable rung and recording its outcome |
| 10 | Every reported absence names both the sources checked and the sources left unchecked — no bare "unsourced" / "not found" | run | revisit before presenting |
| 11 | **Coverage ledger fully marked** — when Phase 0 wrote `research-checklist.md`, `${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh <ledger>` exits 0. Cite the **exit status**, not a reading of the table: a model cannot reliably audit its own checklist, and a context that wants to be finished is exactly the one grading it. The script fails closed — a ledger it cannot parse exits 2, and 2 is a FAIL, never a pass. Not applicable when Phase 0 recorded the corpus as unbounded | run, **script verdict** | Phase 0 — cover the unmarked items, or narrow the corpus explicitly |

**Authoritative + consensus, reconciled:** the primary source is the SPINE of each claim; independent corroborators are the CONFIRMATION. When a top-ranked blog consensus contradicts the primary, the primary wins and the conflict is flagged explicitly — consensus never overrides a fetched authoritative source. Subagent returns are Tier 3 (synthesis), not corroborators, until their cited primaries are fetched this turn. Zero tolerance for false positives: a claim that cannot pass the gate is a **Gap**, not a finding — report it as such, never launder it into the answer. Report the gate result (pass, or which criterion failed and what you re-ran); no limit on iterations.

> **Scoped exception — a dispatched run of THIS skill is not a Tier-3 subagent return.** The Tier-3 rule targets an ad-hoc subagent handing back synthesis with no captured primaries, and it stays in force for that. It does not reach a `discovery:researcher` run that executed this discipline and wrote every primary URL into the artifact: **the tier attaches to the artifact and the sources captured in it, never to the transport that carried the pointer.** Read literally without this exception, dispatch-by-default would demote every run to the tier criterion 1 refuses, and this skill's routing section would contradict its own gate. The exception is exactly as wide as its evidence: a return whose artifact does not carry the fetched primaries is Tier 3 like any other summary, and a missing or mismatched `preload_token` means the discipline never ran at all, so that run is discarded rather than tiered.

## Output Format

Present research findings as — and if invoked standalone present them directly, while inside a larger workflow they feed the subsequent planning step:

1. **Summary** — 2-3 sentence answer to the research question
2. **Evidence table** — `Claim | Sources (Tier 0/1 entries cite the URL/command fetched THIS turn) | Tier | Tool diversity | Confidence`
3. **Fetch log** — the written record criteria 6 and 9 are graded against, so it is WRITTEN, not recalled. One entry per fetch PER CLAIM: `Claim | URL or command | artifact-ladder rung | tool used | outcome`. The claim key is not decoration — criterion 9 is evaluated per accepted claim, and one artifact routinely carries claim A while lacking claim B, so an unkeyed outcome cannot show which claim it answers. Each accepted claim carries the entry for the rung it came from AND one for every rung ABOVE it, whose outcome states which of the four it was — carries the claim; **does not exist** for this claim class, the bypass outcome a probe alone can establish and the normal result for rung 1; was fetched and searched and does not carry the claim; or unreachable after escalation (which is also a Gap row). The middle two are not interchangeable: nonexistence is what a probe settles, and lacking-the-claim is only ever settled by the fetch, so collapsing them is what would let a probe stand in for reading the artifact. For a claim criterion 6 applies to — one whose subject ships releases — the changelog rung is required on top of that walk, not by it: the cross-check is unconditional at every rung, so such a claim sourced from a rung above the changelog still carries its own latest-release/changelog entry. That entry's outcome is COMPOSITE, because one changelog fetch can serve the ladder walk and the cross-check at once: `<ladder outcome> — <confirmed-latest version> (<release date>) — <verdict>`. The ladder half is the four-value vocabulary above, present exactly when the walk reaches this rung — the claim came from the changelog itself or from a rung below it; a claim sourced from a rung ABOVE the changelog has no ladder half here and its entry opens at the version. The verdict half is **current** (the claim holds as of that release), **invalidated** (a major bump or a superseding change since the cited doc — the claim returns to Phase 2), or **unresolved** (the latest release could not be confirmed, or its bearing on the claim could not be settled — a Gap row, exactly as an unreachable rung is). Criterion 9 reads the ladder half and criterion 6 the verdict; neither half stands in for the other, and a rung recorded as fetched without its verdict leaves the recency gate graded from recollection, which is exactly what this log exists to prevent. A claim criterion 6 does not reach — foundational doctrine and anything else with no upstream release stream — carries the ladder walk alone; there is no changelog artifact to cite and none is expected
4. **Conflicts** — disagreements between sources (flagged explicitly; primary wins over blog consensus)
5. **Gaps** — claims not at ≥1 primary + 2 independent corroborators, OR LOW confidence (flagged for follow-up). A gap asserting absence names the sources checked AND the sources left unchecked — never a bare "not found"
6. **Recency status** — primary-source age per tool/library claim
7. **Project fit** — how findings align with the consuming project's conventions and stated direction
8. **Outcome gate result** — pass, or which criterion failed and what was re-run

## Final step: persist artifact for handoff

Write the research output to `<memory_dir>/<slug>/RESEARCH.md` — a memory-tier artifact, never committed, and the authoritative summary of the stage: a fresh session must be able to resume planning reading only it. Destination, slug, and runtime guards resolve per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).

**`RESEARCH.md` is always an INDEX**, at every size — not only past an overflow threshold. It carries the Task restatement, a one-line abstract per sidecar copied verbatim from that sidecar's header, a section → file + anchor table, and the Next-stage-handoff. The Output Format's content lives in sibling `RESEARCH-<section>.md` sidecars in the same directory, each opening with a machine-readable YAML header so a consumer can grep headers, then read exactly one file.

**One writer per slice.** The index and `research-checklist.md` have fixed names, so two runs writing the same slice overwrite each other's index and ledger. **If the slice root already holds a `RESEARCH.md` from unrelated work, or the parent is running several topics in parallel, each run gets its own sub-slice** `<memory_dir>/<slug>/<topic-slug>/` and writes the normal filenames inside it. The run reports the path it actually used — never the default — so the parent's verification request targets the artifact this run produced rather than someone else's. A parent fanning out over N topics assigns the N sub-slices up front, in the dispatch envelope, and synthesizes the slice-root `RESEARCH.md` from their indexes afterwards; a worker never picks its own sub-slice to avoid two workers picking the same one.

**Read [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md) before writing the first sidecar** — the header is a schema a verifier parses, not a free-form preamble, and an improvised one silently costs criterion 4 its evidence. Non-negotiable: `claims[]` is a LIST, each entry carrying its own `confidence` and its own `sources[]` of `{url, tier, pool}`. A single top-level `confidence` or a flat `sources` list collapses per-claim provenance into a document-level assertion, which is exactly what makes independence ungradeable. The header also carries `topic`, `section`, `abstract`, and `produced_by`. **Intra-task pivot — delete stale research, don't layer.** If the approach you researched is abandoned mid-task for a different direction *before shipping*, delete the now-stale section and re-run on the new direction rather than keeping both — a superseded section misleads the planning step into planning against a dead approach. Failure modes this skill has actually hit: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/gotchas.md`.

## What this skill does NOT do

- **Does not make decisions** — presents verified evidence; the planning step (or user) decides
- **Does not write code** — researches only; execution is a separate step
- **Does not skip phases for "simple" topics** — task size does NOT reduce depth. All phases always run
- **Does not present training-data knowledge as current fact** — Tier 3 recall must be promoted to Tier 0/1 before claim acceptance

## See also

- `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md` — source tiers, recency gates, broad-topic recipe, falsification recipe, tool-ecosystem fallback, confidence calibration, source-quality red flags, observed failure patterns
