---
description: "Multi-source external research in chained phases, corpus enumeration, broad, targeted + falsification, preferred sources, with per-claim source tiers, recency checks, a coverage ledger, and a binary outcome gate before presenting. Dispatches a fresh-context subagent by default so the research transcript stays out of the main conversation, with a documented inline escape hatch. Use when: 'research this', 'verify a technical claim', 'evaluate libraries or approaches', 'compare X vs Y', 'is this still current', 'find the authoritative source', 'what do the official docs say', or grounding any decision in current authoritative sources instead of training data. This is the right skill for a single topic, including a small one. For a multi-topic or workflow-driven pass that fans one question across several dispatches, use research-deep, which layers tiered execution on this same discipline."
argument-hint: "[topic] (e.g., /discovery:research <library> <version> best practices, /discovery:research <framework> hook event schema, /discovery:research <ORM> query optimization)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: research
  summary: Multi-source external research with source tiers and a coverage ledger
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

External research is mandatory before acting on external facts. Goal: **maximum knowledge, maximum consensus, latest information** from authoritative + official sources. Training data drifts, library APIs change, SEO content farms outrank authoritative sources, and AI synthesis tools repackage the same secondary blogs as "multi-source", so cross-tool consensus, primary-source priority and recency verification are what drive accuracy.

Local counterpart: `/discovery:explore` (what IS in the repo); this skill covers what SHOULD BE. For a multi-topic or workflow-driven pass, invoke `/discovery:research-deep` via the Skill tool, which layers tiered execution on this discipline. **Philosophy**: more tokens + more time = more accuracy + less rework. Deploy a **research team**, not a single lookup, and give every invocation full depth regardless of task size.

## Routing. Dispatch by default

**From the main conversation, this skill dispatches the `discovery:researcher` subagent.** Research reads a lot; keeping that out of the orchestrator's context window is the point. The agent runs Phase 0 through the gate's mechanical criteria, writes the artifact set, and returns a file pointer plus a short summary, not the transcript. The parent resolves the **pre-dispatch envelope** first, six fields (topic, reason, memory-slice path, memory root, budget, capability flags), written into the dispatch prompt as the labelled template in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), not as prose the agent has to parse, and owns the **post-dispatch boundary** after: re-surfacing `open_questions`, dispatching the sibling verifier, applying project fit itself, and **writing both results back into the index**, because `verification: pending` says the producer may not self-grade, not that the question is permanently open.

**Run inline instead when any of these holds**, and inline runs the identical discipline; the escape hatch relaxes nothing below:

- **Tight turn-by-turn iteration**. You will redirect the queries as they land. Dispatch is a pre-run choice; the steering loss is mid-run.
- **Cost**, a dispatched run pays full depth every time, including for a one-line version lookup whose doc you can already name.
- **The invoking context is already a subagent**. Dispatch-by-default is scoped to the main-conversation boundary, so a subagent invoking this skill runs it inline. The outer dispatch already supplied the fresh context. Hoisting, not nesting.

**Not an escape-hatch reason:** an un-runnable research gate. Before **dispatching**, probe `--help` on the artifact checker and the coverage checker; before an **inline** research run, probe the coverage checker (criterion 11 still applies inline). A denied or errored probe **halts**. Do not take inline to dodge an un-runnable post-dispatch gate, and do not self-grade the coverage ledger by reading the table. Invocation forms (shebang path, `bash`, PowerShell / Python twin) and the halt rule: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md).

**Discipline-liveness token.** A dispatched agent receives this body through its `skills:` preload, and a preload that fails to resolve is skipped **silently**. Logged to the debug log and nowhere else. The disk fallback Reads this same file, so a matching `preload_token` is file-identity, **not** proof that preload fired.

```text
discovery-research-preload-4c1f9a
```

A missing or mismatched token is a **hard failure: the parent discards the run**. Provenance is `preload: fired | fallback`; `fallback` is the accepted recovery. Rationale and the full parent-side contract: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md`.

**Post-dispatch acceptance gate. Parent-side, before the payload is believed.** `status: complete` and `coverage: complete` are the agent's claims about its own run, and a claim is not evidence. Grade the run **off disk**, against the memory-slice path from the parent's own pre-dispatch envelope, **carry that path across the dispatch, because it is this gate's input**, never a path read out of the payload: the failure this gate exists to catch is a payload carrying no pointer at all. In order:

**Pre-dispatch:** create the memory slice and touch `<that slice>/.research-dispatch` as the gate's freshness baseline, then hand that file to the gate as `--newer-than`. Without it a slice that already holds an earlier run's index passes every on-disk check even when this dispatch wrote nothing at all. On an N-topic fan-out one baseline at the slice root serves every sub-slice. **Both shell forms of that command are in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md)**. Copy the one matching this session's shell, because the POSIX form's `touch` is not a command in PowerShell and its directory flag is a parameter error there. Same file carries the envelope template this dispatch owes and the one obligation this gate does not grade (the memory root's `.gitignore` guard).

1. **The payload is well-formed**. `preload_token` matches the token verbatim, `preload:` is `fired` or `fallback`, and an `artifact:` pointer is present. Missing token or artifact is a **failed dispatch** whatever the `status` field says. A missing or unrecognized `preload:` field is an out-of-date agent definition, not a pass. A matching token does not prove preload fired; `preload: fallback` is not a discard.

   **And `topic_as_received` matches the topic the parent actually sent**. Compared against the envelope the parent wrote, not against what it meant. It is the only check here that fires on an input that is present and wrong. A mismatch is a **failed dispatch**: re-dispatch with the topic restated in a form that survives the trip (see the caveat under **Topic**); do not accept the artifact and mentally translate it. A well-formed payload carrying no `topic_as_received` is an out-of-date agent definition, not a pass.
2. **The artifact set is actually on disk, and this run put it there:**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh" <the retained memory-slice path> \
     --index-name RESEARCH.md \
     --newer-than <that slice>/.research-dispatch --expect-index <the payload's artifact: value>
   ```

   Cite the **exit status**, 0 usable, 1 no usable artifact set, 2 ungradeable, not a reading of the directory, because the context most motivated to call the dispatch finished is the one that would be doing the reading. Prefer the shebang path above; `bash "…"` is fine where direct exec is awkward. Only the slice path and `--index-name` are required, and that bare form is still a real gate: every optional check reports `unchecked` rather than passing quietly. Append `--expect-sidecars <n>` when the payload reported a `sidecars:` count, and **drop any flag whose value the payload did not supply**. **The `index=` path in that output is authoritative** downstream: the verifier's `target` and the handoff pointer come from it, not from `artifact:`.

   **Fanning out over N topics, grade each run against the sub-slice IT was assigned, before synthesizing the slice-root index**, a synthesized root index beside its sub-slice indexes is a sanctioned end state and exactly the shape the gate calls ambiguous, so an exit 2 there means the parent fed it the wrong path rather than that a run failed.
3. **The coverage claim is graded from the ledger, not from the payload.** `coverage: complete` mirrors outcome-gate criterion 11, which the run graded on **itself**. When a `research-checklist.md` sits beside the index step 2 named, run `"${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh"` (or the `.py` twin) on `<that index's directory>/research-checklist.md` and cite its exit status. 0 complete, 1 unmarked rows, 2 ungradeable, and **both non-zero values are FAILs**. A gate that could not run is also a FAIL, never a table reading. No ledger on disk is correct **only** when the artifact records the corpus as unbounded; a bounded corpus with no ledger is a Phase 0 that never ran, whatever the payload says.

   Two limits here are deliberate, and together they are why the ladder clears the slice before any re-dispatch: `--newer-than` binds the **index**, never the ledger, and the ledger gate reads marks rather than provenance, so a ledger an earlier run left behind grades as this one's whenever the new run wrote none.

**Any non-zero exit halts the workflow, and a gate that could not run at all is a FAIL, never a skip.** An invocation above that is denied, prompts and is declined, or errors out halts exactly as a non-zero exit does; do not fall back to reading the directory. (This plugin ships no `allowed-tools` grant, and that is a sourced conclusion rather than an omission: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md).) Do **not** proceed to planning, a decision, or an edit on research that did not happen. Proceeding is the damage a silently-empty return causes; the missing artifact is only how it starts. Recovery ladder, and the resume-before-discard ordering it takes: [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md).

**One named exception, and it is an exception to the halt, not to the gate.** Exit 1 with `persistence: by-value` in the payload means the agent finished and its environment refused every write. There the parent **writes the slice itself** from the artifact bodies the payload carries verbatim, into the memory-slice path it resolved before dispatch, and then **re-runs the identical checks above, the artifact gate always, and the coverage-ledger gate whenever a ledger was owed.** The workflow proceeds only when every check that applied comes back 0; otherwise the halt stands and the ladder resumes at the rung it was on.

Read the by-value rung before performing that write: [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md). It carries the two conditions that bind the write (filename checking and the unchanged unbounded-corpus rule) and why a by-value payload of findings rather than artifact bodies is a failed dispatch rather than a fallback.

## Topic

Research the following topic: $ARGUMENTS

**A dispatched run does not read that line.** The topic does not reach a preloaded body by argument substitution, and a non-fork subagent has no conversation to fall back on, so **do not rely on seeing an unfilled slot**. Whatever the line above renders as, a dispatched run takes its topic from the dispatch prompt, and an absent one is a parent-envelope failure the agent reports rather than repairs. What is and is not documented about that path: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md). Running **inline** with no topic supplied above, infer it from the conversation. Identify the claim, decision, or implementation being worked on and research that.

**Caveat, a `${CLAUDE_…}`-shaped token in a topic may not arrive as you typed it**, which is a different question from the paragraph above and not evidence for or against it. What was observed, what is documented, what is not, and the practical rule: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md) ("A different question"). The `topic_as_received` echo-back in the acceptance gate is what catches it whichever way the substitution actually runs.

## Mandatory disciplines (non-negotiable)

Full recipes and rationale: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md` (also the canonical source-tier table for this plugin).

1. **3 phases minimum**. Phase 1 (broad), Phase 2 (targeted, informed by Phase 1, includes falsification), Phase 3 (preferred-sources / tool-ecosystem fallback)
2. **Queries scale to open questions: the floor is a starting point, not a target.** Phase 1 opens with ≥3 queries to seed the evidence base; Phase 2 and Phase 3 each run **one query per unresolved gap/conflict** surfaced by the prior phase's written analysis (≥3, no upper cap). Stopping at the floor while gaps remain is a violation. Read every floor below as "at least," never "exactly"
3. **3 distinct tool types minimum per phase**. Using only one search engine + one synthesis tool for a phase is a violation; mix in direct fetches, doc-MCP servers, `gh api`, or documentation agents your environment provides
4. **4+ distinct tool types across the topic**. Phases cannot share the same 3 tools end-to-end. Cross-phase tool diversity is the consensus-driving mechanism
5. **Source-tier ratio per claim**. Every accepted claim has ≥1 Tier 0/1 (primary source captured this turn) PLUS ≥2 independent corroborators, REGARDLESS of how authoritative the primary is: a canonical doc does not waive corroboration (it can be stale). Three synthesis-tool citations of three blogs = 1 Tier 2 source, NOT 3. Track diversity per claim
6. **Recency gate, first-party docs lag releases**, one query MUST fetch the LATEST upstream changelog or release notes this turn and confirm the claims are current as of it. A major version bump invalidates prior docs, first-party included; treat any doc-vs-changelog lag as a conflict to resolve, not a closed answer. The 30/14/90-day staleness windows: the discipline file's "Recency gate"
7. **One falsification query in Phase 2 (MANDATORY)**. Phase 2 must include exactly one query that attempts to FALSIFY the leading hypothesis from Phase 1
8. **Broad-topic auto-detect → doubled minimums**, when the topic involves 2+ vendors / 2+ tools / 3+ proper-noun products / comparison ("X vs Y") / migration ("X replaces Y") → 6+ queries per phase, 12+ total, 5+ tool types, 4+ Tier 0/1 sources per claim
9. **Phases chain through a WRITTEN analysis**. Phase 2 consumes the gap/conflict/leading-hypothesis list emitted at the end of Phase 1; each Phase 2 query maps to a named entry in it. Phase 3 chains the same way off the Phase 1+2 list. A query not traceable to a prior-phase gap is unchained, the written list IS the broad→deep link, intent is not
10. **Task size does NOT reduce phase count**, a one-line config change gets the same treatment as a multi-file feature
11. **Confidence tracked per claim**. HIGH / MEDIUM / LOW per the discipline file's "Confidence calibration." Do NOT accept LOW-confidence claims as a basis for code edits. Iterate until HIGH
12. **Primary source fetched directly, not via the SERP**. For every accepted claim, name the canonical doc home and fetch it directly with whatever direct-fetch tool is connected this session, top-down through the discipline file's artifact ladder (an announcement page is not the vendor's deepest artifact); SERP + synthesis tools only DISCOVER what to fetch and find corroborators, never serve as the terminal source
13. **Outcome gate before presenting (MANDATORY)**, the run self-checks its own evidence table + written gap lists + fetch log against binary criteria; any FAIL returns to the named phase (see "Outcome gate")
14. **Bounded corpora are enumerated before they are searched (MANDATORY)**, when the topic has a finite, knowable set of things to cover, Phase 0 writes `research-checklist.md` naming every item and its per-item depth criterion BEFORE any query runs, and the gate fails on any unmarked row. Distinct from discipline 9: the gap list chases *unknowns* surfaced by searching, this enforces exhaustive coverage of a set that was knowable up front. Recipe: the discipline file's "Corpus enumeration"

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

**Launch ≥3 queries across ≥3 source categories in parallel**. Official docs, upstream source + releases, package registry, spec/standard, AI-synthesis (discovery only, never a terminal source), community corroborators. Take stock of what is actually connected THIS session and map the categories onto it; never hard-depend on one server. The category table, the two standing preferences, and why category diversity is the mechanism rather than a quota: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/source-categories.md`.

### Phase 1 output. Write this list before composing any Phase 2 query

**STOP. Emit a written analysis block**. This IS the broad→deep chaining mechanism. Phase 2 queries are composed FROM it, not alongside it. The block MUST contain:

- **Leading hypothesis**. What the evidence points toward
- **Gaps** (numbered). Each claim not yet backed by ≥1 primary (Tier 0/1) + 2 independent corroborators, plus any open question. Every numbered gap earns a Phase 2 query, the gap count sets the Phase 2 query count
- **Conflicts** (numbered). Disagreements between sources; each earns a resolving Phase 2 query
- **Tool-diversity audit**, distinct tool types used; if <3, this phase failed, re-run before proceeding
- **Recency status**. Upstream changelog/release fetched? If not, queue for Phase 2
- **Falsification candidate**, the most load-bearing claim that, if wrong, invalidates the rest. That's the Phase 2 falsification target

Phase 2 is not "launch 3 queries". It is "close every numbered gap + conflict above, plus the one falsification query." If that totals 6, run 6.

## Phase 2: Targeted + Falsification (one query per Phase 1 gap/conflict + 1 mandatory falsification)

Objective: fill gaps, resolve conflicts, strengthen low-confidence claims, AND attempt to break the leading hypothesis.

**One query MUST be a falsification attempt** against the Phase 1 leading hypothesis. See the discipline file's "Falsification step" for query patterns. Without this step, Phase 2 is confirmation bias by default.

**Remaining queries. One per numbered gap/conflict from the Phase 1 list:**

- **Gap-filling**. One query per numbered Phase 1 gap
- **Conflict resolution**. Queries that specifically test contradicting claims with version-specific terms
- **Primary-source deep dives**. Fetch the primary directly (raw release notes / docs pages) for claims needing Tier 1 confirmation
- **Recency verification**, if not done in Phase 1, fetch the upstream changelog/releases NOW

### Phase 2 output (before proceeding to Phase 3)

**STOP and analyze Phase 1+2 combined results.** Update the gap/conflict list. Identify Phase 3 sources (preferred-source authors OR the tool-ecosystem fallback if no author covers the domain).

## Phase 3: Preferred Sources OR Tool-Ecosystem Fallback (3+ queries)

Objective: cross-reference findings against trusted thought leaders OR upstream maintainers.

**Path A, a preferred-source roster exists.** If the consuming project maintains one (trusted authors/domains in its `CLAUDE.md`, rules, or docs), identify 3+ relevant entries and launch 3+ queries using those author names as search qualifiers.

**Path B. No roster, or no listed author covers the domain (typical for tool-ecosystem topics).** MUST cite all three:

1. **Official maintainer**, the vendor's own social / GitHub / blog
2. **Upstream repo changelog or releases**. `gh api repos/<owner>/<repo>/releases` OR a raw `CHANGELOG.md` fetch this turn
3. **One recognized industry authority**, a top-voted community post or named-author practitioner blog

Tool-ecosystem Phase 3 fallback playbook: the discipline file's "Tool-ecosystem Phase 3 fallback".

## Phase 4 (conditional): Additional follow-up

If Phases 1-3 still have gaps, conflicts, or LOW-confidence claims, launch targeted queries until every claim reaches HIGH confidence per the discipline file's "Confidence calibration". There is no limit on additional phases. Self-critique the approach as you go.

## Research principles (apply throughout all phases)

- **Authoritative sources first**. Tier 0 (direct tool output) > Tier 1 (official docs fetched this turn) > Tier 2 (recognized authors, vetted blogs) > Tier 3 (training-data recall, NOT acceptable; must promote before acting). Tier table: the discipline file
- **Source code as spec**, when the topic is "how does library/implementation X behave" and X's source is reachable (GitHub, vendored dependency, package cache), READ the source: it outranks every doc about it, even across languages. Port/reimplementation topics carry a semantics map in `RESEARCH.md`. Matched excerpts (source ↔ target), gotcha notes, edge-case table
- **Version-aware**, always include version numbers in searches
- **Avoid SEO content farms**. Down-rank listicles, repackaged content, vendor marketing pages. See the discipline file's "Source-quality red flags"
- **Summarization loss is bounded by the artifact, not by staying inline**, the evidence table, fetch log and gap lists are on disk, so a consumer needing a detail reads it rather than re-running. Use parallel workers for breadth within a phase; never let one hand back a verdict whose primary it alone read
- **No shortcuts for small tasks**, a "quick config change" still gets the full discipline
- **No parallel MCP calls to the same stdio server**. That transport is serial. Run sequentially within a server, parallelize across different servers/tools
- **Graceful degradation**, if a tool category is unavailable this session, substitute equivalent coverage and document the gap; don't lower the bar

## Outcome gate (run before presenting. MANDATORY)

Research is not done when the phases finish. It's done when it passes this gate. Check what the run ACHIEVED against what good research requires, **grounded in the run's own artifacts** (the evidence table, the Phase 1/2 written gap lists, the fetch log), NOT in your recollection of "did I do a good job." The same model that satisficed the bars runs this check, so only artifact-grounded binary criteria bite.

Each criterion is binary. Read it off an artifact, not from memory. **Any FAIL returns to the named phase; do not present until all pass.** And **the Owner column is not decoration.** Rows the run can read off an artifact stay with the run. A row where the run would judge the quality of *its own choices* belongs to a **verifier**, a fresh context that never saw the run, dispatched by the parent as a sibling once the artifact is on disk. One row needs the consuming project's conventions and belongs to the **parent**. So a dispatched run returns `verification: pending` and renders no verdict on a verifier row; an inline run hands those rows to a fresh context too.

| # | Binary criterion | Owner | FAIL → |
|---|---|---|---|
| 1 | Every claim row has ≥1 Tier 0/1 source whose URL/command was captured THIS turn | run | Phase 2. Fetch the primary directly |
| 2 | No claim row's sources are ALL Tier-2 secondary | run | Phase 2. Get a primary |
| 3 | Every Phase 2/3 query traces to a numbered gap/conflict in a written analysis block | run | re-run the phase chained to the list |
| 4 | Every claim has ≥2 INDEPENDENT corroborators (not 2 cites of one upstream pool) | **verifier** | Phase 2. Widen sources |
| 5 | The Phase 2 falsification query ran and is recorded | run | Phase 2. Run it |
| 6 | Recency gate satisfied for every tool/library/API claim: the LATEST upstream changelog/release was fetched THIS turn and cross-checked against the claim. Read the confirmed-latest release and the verdict off the fetch log's changelog entry, an absent verdict or an `invalidated` one FAILs, and `unresolved` passes only as an enumerated Gap, never under an accepted claim. Windows, and what a major bump invalidates: the discipline file's "Recency gate" | run | Phase 2. Fetch changelog |
| 7 | Every accepted claim is HIGH confidence | **verifier** | Phase 4 follow-up. Iterate to HIGH |
| 8 | Project fit checked against the consuming project's own conventions and stated direction | **parent** | revisit before presenting |
| 9 | For every ACCEPTED claim taken from any publisher's own artifacts, vendor, OSS maintainer, standards body alike, the fetch log ACCOUNTS FOR every artifact-ladder rung above the one the claim came from, each carrying one of the outcome values and none left unaccounted. Rungs, outcome vocabulary, and what earns nonexistence rather than `unresolved`: the discipline file's "Primary-source-first protocol". A rung that exists, is reachable, and carries the claim IS where the claim comes from | run | Phase 2. Walk the ladder from rung 1, fetching and searching each reachable rung and recording its outcome |
| 10 | Every reported absence names both the sources checked and the sources left unchecked. No bare "unsourced" / "not found" | run | revisit before presenting |
| 11 | **Coverage ledger fully marked**, when Phase 0 wrote `research-checklist.md`, `${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh <ledger>` (or `.py`) exits 0. Cite the **exit status**, not a reading of the table: the context that wants to be finished is the one grading it. It fails closed, a ledger it cannot parse exits 2, and 2 is a FAIL; a script that could not run at all is the same FAIL, never a skip or a hand-grade. Not applicable when Phase 0 recorded the corpus as unbounded | run, **script verdict** | Phase 0. Cover the unmarked items, or narrow the corpus explicitly |

**Authoritative + consensus, reconciled:** the primary is the SPINE of a claim and independent corroborators are the CONFIRMATION, so when blog consensus contradicts the primary the primary wins and the conflict is flagged. Subagent returns are Tier 3 until their cited primaries are fetched this turn. **A claim that cannot pass the gate is a Gap, not a finding**, never laundered into the answer. Report the gate result (pass, or which criterion failed and what you re-ran); no limit on iterations.

> **Scoped exception, a dispatched run of THIS skill is not a Tier-3 subagent return**, because the tier attaches to the artifact and the sources captured in it, never to the transport that carried the pointer. Its exact width, and the two returns it does not cover: the discipline file's "Source tiers".

## Output Format

Present research findings as, and if invoked standalone present them directly, while inside a larger workflow they feed the subsequent planning step:

1. **Summary**. 2-3 sentence answer to the research question
2. **Evidence table**. `Claim | Sources (Tier 0/1 entries cite the URL/command fetched THIS turn) | Tier | Tool diversity | Confidence`
3. **Fetch log**, the written record criteria 6 and 9 are graded against, so it is WRITTEN, not recalled. One entry per fetch PER CLAIM: `Claim | URL or command | artifact-ladder rung | tool used | outcome`, and each accepted claim carries the entry for the rung it came from AND one for every rung above it. **The outcome vocabulary is a parsed schema, not free text**. Five values, three of which look interchangeable and are not, plus the composite changelog entry criterion 6 grades. Write it to the spec in `${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md` ("The fetch log")
4. **Conflicts**. Disagreements between sources (flagged explicitly; primary wins over blog consensus)
5. **Gaps**. Claims not at ≥1 primary + 2 independent corroborators, OR LOW confidence (flagged for follow-up). A gap asserting absence names the sources checked AND the sources left unchecked, never a bare "not found"
6. **Recency status**. Primary-source age per tool/library claim
7. **Project fit**. How findings align with the consuming project's conventions and stated direction
8. **Outcome gate result**. Pass, or which criterion failed and what was re-run

## Final step: persist artifact for handoff

Write the research output to `<memory_dir>/<slug>/RESEARCH.md`, a memory-tier artifact, never committed, and the authoritative summary of the stage: a fresh session must be able to resume planning reading only it. Destination, slug, and runtime guards resolve per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).

**`RESEARCH.md` is always an INDEX**, at every size, not only past an overflow threshold. It carries the Task restatement, a one-line abstract per sidecar copied verbatim from that sidecar's header, a section → file + anchor table, and the Next-stage-handoff. The Output Format's content lives in sibling `RESEARCH-<section>.md` sidecars in the same directory, each opening with a machine-readable YAML header so a consumer can grep headers, then read exactly one file.

**One writer per slice.** The index and `research-checklist.md` have fixed names, so two runs writing one slice overwrite each other. When the slice root is occupied, or a parent is running several topics in parallel, **each run writes its whole set into its own sub-slice** `<memory_dir>/<slug>/<topic-slug>/` under the normal filenames and reports the path it used. The parent assigns those sub-slices; a worker never picks its own. Why renaming the index instead is not an option: the artifact-shape file.

**Read [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md) before writing the first sidecar**, the sidecar header and the fetch log are both schemas a verifier parses, and an improvised one silently costs criteria 4, 6 and 9 their evidence. Carry this much into the read: `claims[]` is a LIST, each entry with its own `confidence` and its own `sources[]` of `{url, tier, pool}`.

**Intra-task pivot. Delete stale research, don't layer.** If the approach you researched is abandoned mid-task for a different direction *before shipping*, delete the now-stale section and re-run on the new direction; a superseded section makes the planning step plan against a dead approach. Failure modes this skill has actually hit: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/gotchas.md`.

## What this skill does NOT do

- **Does not make decisions**. Presents verified evidence; the planning step (or user) decides
- **Does not write code**. Researches only; execution is a separate step
- **Does not skip phases for "simple" topics**. Task size does NOT reduce depth. All phases always run
- **Does not present training-data knowledge as current fact**. Tier 3 recall must be promoted to Tier 0/1 before claim acceptance

## See also

- `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md`. Source tiers, recency gates, broad-topic recipe, falsification recipe, tool-ecosystem fallback, confidence calibration, source-quality red flags, observed failure patterns
