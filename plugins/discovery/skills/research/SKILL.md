---
description: "Multi-source external research with source tiers, recency checks, and a coverage ledger. Dispatches a subagent by default. Use when: 'research this', 'verify a technical claim', 'evaluate libraries or approaches', 'compare X vs Y', 'is this still current', 'find the authoritative source', 'what do the official docs say'. This is the right skill for a single topic (breadth=low narrows it) and for a local folder outside any repository or machine state. For a multi-topic pass, use research-deep."
argument-hint: "[breadth=low|medium] [topic]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: research
  summary: Multi-source external research with source tiers and a coverage ledger
---

**Arguments.** `[breadth=low|medium] [topic]`. e.g., /discovery:research breadth=low <library> <version> changelog, /discovery:research <framework> hook event schema, /discovery:research <ORM> query optimization

## Routing. Dispatch by default

**From the main conversation, this skill dispatches the `discovery:researcher` subagent.** Research reads a lot; keeping that out of the orchestrator's context window is the point. The agent returns a file pointer plus a short summary, not the transcript. The parent resolves the **pre-dispatch envelope** and baseline first ("Pre-dispatch envelope and baseline" below) and owns the **post-dispatch boundary** after: re-surfacing `open_questions`, dispatching the sibling verifier, applying project fit itself, and **writing both results back into the index**, because `verification: pending` says the producer may not self-grade, not that the question is permanently open. Inline runs, and why an un-runnable gate is no reason for one: "Running inline" below.

**Discipline-liveness token.** The dispatched agent echoes this token as `preload_token`, and a missing or mismatched one is a **hard failure: the parent discards the run**.

```text
discovery-research-preload-4c1f9a
```

The disk fallback Reads this same file, so a matching token is file-identity, **not** proof that preload fired. Provenance is `preload: fired | fallback`; `fallback` is the accepted recovery. Why a token at all: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md` ("Discipline liveness: why a token at all").

**Post-dispatch acceptance gate. Parent-side, before the payload is believed.** `status: complete` and `coverage: complete` are the agent's claims about its own run, and a claim is not evidence. Grade the run **off disk**, against the memory-slice path from the parent's own pre-dispatch envelope, **carry that path across the dispatch, because it is this gate's input**, never a path read out of the payload, which may carry no pointer at all. In order:

1. **The payload is well-formed**. `preload_token` matches the token verbatim, `preload:` is `fired` or `fallback`, and an `artifact:` pointer is present. Missing token or artifact is a **failed dispatch** whatever the `status` field says. A missing or unrecognized `preload:` field is an out-of-date agent definition, not a pass.

   **And `topic_as_received` matches the topic the parent actually sent**. Compared against the envelope the parent wrote, not against what it meant. A mismatch is a **failed dispatch**: re-dispatch with the topic restated in a form that survives the trip (see "Topic caveats"); do not accept the artifact and mentally translate it. A well-formed payload carrying no `topic_as_received` is an out-of-date agent definition, not a pass.

2. **The artifact set is actually on disk, and this run put it there**, graded against the `.research-dispatch` baseline touched before dispatch:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh" <the retained memory-slice path> \
     --index-name RESEARCH.md \
     --newer-than <that slice>/.research-dispatch --expect-index <the payload's artifact: value>
   ```

   Cite the **exit status**, 0 usable, 1 no usable artifact set, 2 ungradeable, not a reading of the directory, because the context most motivated to call the dispatch finished is the one that would be doing the reading. `bash "…"` is fine where direct exec is awkward. Only the slice path and `--index-name` are required, and that bare form is still a real gate: every optional check reports `unchecked` rather than passing quietly. Append `--expect-sidecars <n>` when the payload reported a `sidecars:` count, and **drop any flag whose value the payload did not supply**. **The `index=` path in that output is authoritative** downstream: the verifier's `target` and the handoff pointer come from it, not from `artifact:`.

   **Fanning out over N topics, grade each run against the sub-slice IT was assigned, before synthesizing the slice-root index.** The gate grades exactly the path it is given, so a slice-root invocation grades only the synthesis, never a dispatched run. The synthesis then goes to a fresh verifier for criterion 12 before it is surfaced: the dispatch contract's fan-out section.

3. **The coverage claim is graded from the ledger, not from the payload.** `coverage: complete` mirrors outcome-gate criterion 11, which the run graded on **itself**. When a `research-checklist.md` sits beside the index step 2 named, run `"${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh"` (or the `.py` twin) on `<that index's directory>/research-checklist.md` and cite its exit status. 0 complete, 1 unmarked rows, 2 ungradeable, and **both non-zero values are FAILs**. No ledger on disk is correct **only** when the artifact records the corpus as unbounded; a bounded corpus with no ledger is a Phase 0 that never ran, whatever the payload says.

4. **Source applicability is graded from the headers, not from the payload.** `applicability:` mirrors criterion 13. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/check-source-applicability.py" <that index's directory> --expect-evidence-use <the envelope's Evidence use value>` and cite its exit status: 0 pass, 1 a violation, 2 ungradeable, and both non-zero values are FAILs.

**Any non-zero exit halts the workflow, and a gate that could not run at all is a FAIL, never a skip.** An invocation above that is denied, prompts and is declined, or errors out halts exactly as a non-zero exit does; do not fall back to reading the directory. Do **not** proceed to planning, a decision, or an edit on research that did not happen. Recovery ladder, and the resume-before-discard ordering it takes: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md`. Clear the slice before any re-dispatch: `--newer-than` binds the **index**, never the ledger, and the ledger gate reads marks, not provenance.

**One named exception, and it is an exception to the halt, not to the gate.** Exit 1 with `persistence: by-value` in the payload means the agent finished and its environment refused every write. The parent then **writes the slice itself** and re-runs the identical checks that applied; the workflow proceeds only when every one returns 0. Read the by-value rung before writing: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md` ("Recovery ladder"), which binds the write and says when a by-value payload is a failed dispatch.

**Then dispatch the sibling verifier**, once every gate above exits 0, for every row the outcome gate's Owner column marks verifier:

```text
Agent({
  subagent_type: "discovery:research-verifier",
  description: "Verify research: <topic>",
  prompt: "Target: <the index= path the artifact gate printed>
           Rows: 4, 7, 12, 14"
})
```

Write its `verification_line` over `verification: pending`; a FAIL row returns to its phase (bounded at `Budget: low`). **On the cost path** (you skip the verifier for cost) write `verification: skipped (cost)`; never leave `pending` after this boundary. Values: `${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md` ("The `verification:` values"). Brief, write-back, project fit: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md` ("The orchestration boundary").

## Outcome gate (run before presenting)

Research is not done when the phases finish. It's done when it passes this gate. Check what the run ACHIEVED against what good research requires, **grounded in the run's own artifacts** (the evidence table, the Phase 1/2 written gap lists, the fetch log), NOT in your recollection of "did I do a good job." The context that ran the phases is the one grading them, so only artifact-grounded binary criteria bite.

Each criterion is binary. **Any FAIL returns to the named phase (bounded at `Budget: low`: "Effort, source breadth"); do not present until all pass.** And **the Owner column is not decoration.** Rows the run can read off an artifact stay with the run. A row where the run would judge the quality of *its own choices* belongs to a **verifier**, a fresh context that never saw the run, dispatched by the parent as a sibling once the artifact is on disk. One row needs the consuming project's conventions and belongs to the **parent**. So a dispatched run returns `verification: pending` and renders no verdict on a verifier row; an inline run hands those rows to a fresh context too. The Owner column governs over any enumeration of these rows in an agent definition or sibling skill.

| # | Binary criterion | Owner | FAIL → |
|---|---|---|---|
| 1 | Every claim row has ≥1 Tier 0/1 source whose URL/command was captured THIS turn | run | Phase 2. Fetch the primary directly |
| 2 | No claim row's sources are ALL Tier-2 secondary | run | Phase 2. Get a primary |
| 3 | Every Phase 2/3 query traces to a numbered gap/conflict in a written analysis block | run | re-run the phase chained to the list |
| 4 | Every accepted claim has ≥2 INDEPENDENT `current` corroborators (not 2 cites of one upstream pool, as in the discipline file's "Single-publisher facts"; a `historical` source never counts), or is a first-party content claim flagged `single source` that states why only one publisher exists; a repost is not a second source, and a behavior claim gets no flag | **verifier** | Phase 2. Widen sources |
| 5 | The Phase 2 falsification query ran and is recorded | run | Phase 2. Run it |
| 6 | Recency gate satisfied for every tool/library/API claim: the LATEST upstream changelog/release was fetched THIS turn and cross-checked against the claim. Read the confirmed-latest release and the verdict off the fetch log's changelog entry, an absent verdict or an `invalidated` one FAILs, and `unresolved` passes only as an enumerated Gap, never under an accepted claim. Windows, and what a major bump invalidates: the discipline file's "Recency gate" | run | Phase 2. Fetch changelog |
| 7 | Every accepted claim is HIGH confidence, or `HIGH (single source)` under row 4's flag; a MEDIUM or LOW claim listed in the Gaps section is not accepted | **verifier** | Phase 4 follow-up. Iterate to HIGH or list as a Gap |
| 8 | Project fit checked against the consuming project's own conventions and stated direction | **parent** | revisit before presenting |
| 9 | For every ACCEPTED claim taken from any publisher's own artifacts, vendor, OSS maintainer, standards body alike, the fetch log ACCOUNTS FOR every artifact-ladder rung above the one the claim came from, each carrying one of the outcome values and none left unaccounted. Rungs, outcome vocabulary, and what earns nonexistence rather than `unresolved`: the discipline file's "Primary-source-first protocol". A rung that exists, is reachable, and carries the claim IS where the claim comes from | run | Phase 2. Walk the ladder from rung 1, fetching and searching each reachable rung and recording its outcome |
| 10 | Every reported absence names both the sources checked and the sources left unchecked. No bare "unsourced" / "not found" | run | revisit before presenting |
| 11 | **Coverage ledger fully marked**, when Phase 0 wrote `research-checklist.md`, `${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh <ledger>` (or `.py`) exits 0. Cite the **exit status**, not a reading of the table: the context that wants to be finished is the one grading it. It fails closed, a ledger it cannot parse exits 2, and 2 is a FAIL; a script that could not run at all is the same FAIL, never a skip or a hand-grade. Not applicable when Phase 0 recorded the corpus as unbounded | run, **script verdict** | Phase 0. Cover the unmarked items, or narrow the corpus explicitly |
| 12 | Every accepted claim follows jointly from its cited sources: the claim's primary source measures the claim's variable and population, every cited source passes the variable, population, era and scenario checks or is recorded and not counted toward criterion 4, counter-evidence already read is resolved, and every recorded qualifier survives. Under `evidence_use: publish`, the answer quotes only `current` sources as support. Recipe: the discipline file's "Joint-inference check" | **verifier** | Phase 2. Fetch a source that measures the claim's variable, population, version and scenario, or reattach the qualifier or resolve the counter-evidence in the artifact; else a Gap or Conflicts entry |
| 13 | **Source applicability recorded and consistent**: `${CLAUDE_PLUGIN_ROOT}/scripts/check-source-applicability.py <slice>` exits 0. It checks that every claim names its target `applies_to:`, every source its `published:`, `applies_to:` and `standing:`, that each stored `standing:` matches the one derived from those fields, and that each primary is dated and `current`. Cite the **exit status**; 1 and 2 FAIL, and so does a script that could not run. Applies to every run with claims, inline included | run, **script verdict** | Phase 2. Record the fields, or relabel the source, or find a `current` primary |
| 14 | The index's `accepted:` counts the claims not listed under Gaps; at 0 the Summary opens `Inconclusive: no claim accepted.` A zero with that line passes; a missing or wrong count, or a bare zero, FAILs | **verifier** | revisit before presenting |

**A claim that cannot pass the gate is a Gap, not a finding**, never laundered into the answer. Report the gate result (pass, or which criterion failed and what you re-ran); no limit on iterations. Tier-3 reconciliation: "Reconciling sources at the gate" below.

## Topic

Research the following topic: $ARGUMENTS

A leading `breadth=low` or `breadth=medium` token is not part of the topic: strip it before writing `Topic:` and apply it under "Effort, source breadth". A dispatched run and a run with no topic: "Topic caveats" below.

## Disciplines

Full recipes and rationale: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md` (also the canonical source-tier table for this plugin).

1. **3 phases minimum**. Phase 1 (broad), Phase 2 (targeted, informed by Phase 1, includes falsification), Phase 3 (preferred-sources / tool-ecosystem fallback)
2. **Queries scale to open questions: the floor is a starting point, not a target.** Phase 1 opens with ≥3 queries to seed the evidence base; Phase 2 and Phase 3 each run **one query per unresolved gap/conflict** surfaced by the prior phase's written analysis (≥3, no upper cap). Every floor below is a minimum; a run that stops at the floor while numbered gaps remain has not finished the phase
3. **3 distinct tool types minimum per phase**. One search engine plus one synthesis tool does not meet it; mix in direct fetches, doc-MCP servers, `gh api`, or documentation agents your environment provides
4. **4+ distinct tool types across the topic**. Phases cannot share the same 3 tools end-to-end. Cross-phase tool diversity is the consensus-driving mechanism
5. **Source-tier ratio per claim**. Every accepted claim has ≥1 Tier 0/1 (primary source captured this turn) PLUS ≥2 independent corroborators that cover the claim's target version (a `historical` source is recorded, never counted), however authoritative the primary (a canonical doc can be stale). Three synthesis-tool citations of three blogs = 1 Tier 2 source, NOT 3. Track diversity per claim. This is criterion 4's floor; acceptance also needs HIGH (criterion 7). The one exception to the floor: the discipline file's "Single-source first-party content claims"
6. **Recency gate, first-party docs lag releases**, one query fetches the latest upstream changelog or release notes this turn and confirms the claims are current as of it. A major version bump invalidates prior docs, first-party included; treat any doc-vs-changelog lag as a conflict to resolve, not a closed answer. The 30/14/90-day staleness windows: the discipline file's "Recency gate"
7. **One falsification query in Phase 2**. Phase 2 includes exactly one query that attempts to falsify the leading hypothesis from Phase 1; without it Phase 2 confirms Phase 1 by default
8. **Broad-topic auto-detect → doubled minimums**, when the topic involves 2+ vendors / 2+ tools / 3+ proper-noun products / comparison ("X vs Y") / migration ("X replaces Y") → 6+ queries per phase, 12+ total, 5+ tool types, 4+ Tier 0/1 sources per claim
9. **Phases chain through a WRITTEN analysis**. Phase 2 consumes the gap/conflict/leading-hypothesis list emitted at the end of Phase 1; each Phase 2 query maps to a named entry in it. Phase 3 chains the same way off the Phase 1+2 list. A query not traceable to a prior-phase gap is unchained, the written list IS the broad→deep link, intent is not
10. **Task size does not reduce phase count**, a one-line config change gets the same treatment as a multi-file feature. Only the Effort table reduces it, at the row caller effort or a `breadth=` token selects
11. **Confidence tracked per claim**. HIGH / MEDIUM / LOW per the discipline file's "Confidence calibration." A LOW-confidence claim is not a basis for a code edit; iterate to HIGH or list it as a Gap
12. **Primary source fetched directly, not via the SERP**. For every accepted claim, name the canonical doc home and fetch it directly, top-down through the discipline file's artifact ladder (an announcement page is not the vendor's deepest artifact); SERP + synthesis tools only DISCOVER what to fetch and find corroborators, never serve as the terminal source
13. **Outcome gate before presenting**: the run grades its rows off its own artifacts; verifier rows go to a fresh-context verifier
14. **Bounded corpora are enumerated before they are searched**, when the topic has a finite, knowable set of things to cover, Phase 0 writes `research-checklist.md` naming every item and its per-item depth criterion BEFORE any query runs, and the gate fails on any unmarked row. Distinct from discipline 9: the gap list chases *unknowns* surfaced by searching, this covers every item of a set knowable up front. Recipe: the discipline file's "Corpus enumeration"
15. **Every accepted claim follows from its sources jointly**, name what each source measures and why the claim follows from them together; verbatim quotes are not that evidence. Recipe: the discipline file's "Joint-inference check"

### Effort, source breadth

Caller effort for this run is `${CLAUDE_EFFORT}`. If that reads as a literal placeholder rather than
one of `low`, `medium`, `high`, `xhigh`, or `max`, this body was read directly instead of
skill-loaded, so the substitution never ran: treat the run as `high` and run every phase below.
Dated record: `${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`,
"Harness facts the dispatch design rests on". A dispatched run follows envelope `Source breadth:`
from this load, not the researcher pin. Missing line: `high`, named in the artifact.

| Effort | Source breadth |
|---|---|
| `low` | Phase 0 if bounded, Phase 1 at existing floors and under the cap below, Phase 2 as the mandatory falsification query only (no per-gap expansion). Skip Phase 3 and Phase 4 |
| `medium` | Phase 0 through 2 in full (per-gap Phase 2 queries plus falsification). Skip Phase 3 and Phase 4 |
| `high`, `xhigh`, `max` | Current full workflow |

The Effort row is the ceiling over discipline 8. Rationale and skipped-phase N/A: the discipline
file's "Effort, source breadth".

**`breadth=` narrows, never widens.** A `breadth=low` or `breadth=medium` token in `$ARGUMENTS`
selects that row when it is below caller effort; source breadth is the lower of the two, and
nothing here widens the researcher's `maxTurns: 40`. A dispatched run writes the resolved row to `Source breadth:` and the matching word
to `Budget:` (parent contract, "`Budget:` vocabulary"). Without the token, lowering session effort
before invoking is the other lever. Use `low` for a question about one named artifact, folder, or
version.

**Phase 1 at `low` is capped at 6 web queries and fetches combined**, above the 3-query floor and
below the doubled minimums. For a single named artifact or folder, read it directly first (`Read`,
`Glob`, `Grep`, or a listing) and let what it shows choose the queries; local reads do not count
against the cap. A claim still short of its sources at the cap is a gap named in the artifact, not
a reason to search on.

**The verify-and-rework loop at `low` is bounded.** A verifier FAIL on a verifier-owned row (Owner
column, "Outcome gate") is not reworked: no `SendMessage` resume of the researcher. Record it in the
artifact as a Gap or Conflicts entry, lowering `accepted:` to match (criterion 14), or leave it as the named `verification: fail rows` value, and
present the result with that caveat. Medium and above return a FAIL row to its phase as the gate
routes. Rows the run owns and gate exit codes stay mandatory at every budget, and an ungradeable or
missing artifact still takes the recovery ladder, resume before discard.

## Pre-dispatch envelope and baseline

Resolve these before dispatching. The envelope is six shared fields (topic, reason, memory-slice path, memory root, budget, capability flags) plus research-only `Source breadth:` and `Evidence use:` (`publish` when the output will be quoted outside this session, such as a pull-request reply, an issue, or a document for a third party; else `internal`), written into the dispatch prompt as the labeled lines below, not as prose the agent has to parse:

```text
Topic: <the resolved topic>
Reason: <the decision this feeds, and who the output is for>
Memory slice: <memory_dir>/<slug>/              # the sub-slice on a fan-out or a collision
Memory root: <memory_dir>
Budget: <low|medium|full>, optionally followed by words on the depth this session authorized
Turn budget: <turns of gathering before the agent writes and hands back; at or below the agent's default stop turn (30)>
Capability flags: nested spawning <available|unavailable>
Source breadth: <low|medium|high|xhigh|max>
Evidence use: <internal|publish>
```

At `Budget: low` the parent contract's "`Budget:` vocabulary" sets the `Turn budget:` value. `Source breadth:` is `${CLAUDE_EFFORT}` as this load rendered it (a literal placeholder means the body was read from disk: write `high`). Why each field exists and how a missing one degrades: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), which the dispatch does not need.

**Pre-dispatch:** create the memory slice and touch `<that slice>/.research-dispatch` as the gate's freshness baseline, then hand that file to the gate as `--newer-than`. Without it a slice that already holds an earlier run's index passes every on-disk check even when this dispatch wrote nothing at all. On an N-topic fan-out one baseline at the slice root serves every sub-slice. Run the form matching this session's shell, because the POSIX form's `touch` is not a command in PowerShell and its directory flag is a parameter error there:

```bash
# POSIX shells (bash, zsh, Git Bash)
mkdir -p <memory-slice path> && touch <memory-slice path>/.research-dispatch
```

```powershell
# PowerShell
New-Item -ItemType Directory -Force -Path '<memory-slice path>' | Out-Null
New-Item -ItemType File -Force -Path '<memory-slice path>/.research-dispatch' | Out-Null
```

The one obligation the acceptance gate does not grade (the memory root's `.gitignore` guard) is in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md).

## Running inline

**Run inline instead when any of these holds**, and inline runs the identical discipline; the escape hatch relaxes nothing in this skill:

- **Tight turn-by-turn iteration**. You will redirect the queries as they land. Dispatch is a pre-run choice; the steering loss is mid-run.
- **Cost**, a dispatched run pays full depth every time, including for a one-line version lookup whose doc you can already name. Inline moves that cost into this context without reducing it; `breadth=low` (see "Effort, source breadth") is what reduces it.
- **The invoking context is already a subagent**. Dispatch-by-default is scoped to the main-conversation boundary, so a subagent invoking this skill runs it inline. The outer dispatch already supplied the fresh context. Hoisting, not nesting.

**Not an escape-hatch reason:** an un-runnable research gate. Before **dispatching**, probe `--help` on the artifact checker, the coverage checker, and the source-applicability checker, chained in one call so an unconfigured session sees one prompt; before an **inline** research run, probe the coverage and source-applicability checkers (criteria 11 and 13 still apply inline). A denied or errored probe **halts**. The allow rules `/discovery:setup check` prints cover the probes and the gates alike. Do not take inline to dodge an un-runnable post-dispatch gate, and do not self-grade the coverage ledger by reading the table. Invocation forms (shebang path, `bash`, PowerShell / Python twin) and the halt rule: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md).

## Reconciling sources at the gate

**Authoritative + consensus, reconciled:** the primary is the SPINE of a claim and independent corroborators are the CONFIRMATION, so when blog consensus contradicts the primary the primary wins and the conflict is flagged. Subagent returns are Tier 3 until their cited primaries are fetched this turn.

> **Scoped exception, a dispatched run of THIS skill is not a Tier-3 subagent return**, because the tier attaches to the artifact and the sources captured in it, never to the transport that carried the pointer. Its exact width, and the two returns it does not cover: the discipline file's "Source tiers".

## Topic caveats

**A dispatched run does not read the `Research the following topic:` line.** The topic does not reach a preloaded body by argument substitution, and a non-fork subagent has no conversation to fall back on, so **do not rely on seeing an unfilled slot**. Whatever the `## Topic` line renders as, a dispatched run takes its topic from the dispatch prompt, and an absent one is a parent-envelope failure the agent reports rather than repairs. What is and is not documented about that path: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md). Running **inline** with no topic supplied under `## Topic`, infer it from the conversation. Identify the claim, decision, or implementation being worked on and research that.

**Caveat, a `${CLAUDE_…}`-shaped token in a topic may not arrive as you typed it**, which is a different question from the paragraph above and not evidence for or against it. What was observed, what is documented, what is not, and the practical rule: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md) ("A different question"). The `topic_as_received` echo-back in the acceptance gate is what catches it whichever way the substitution actually runs.

## Repository context. Gather first

**Only when no topic argument was supplied** (the line under `## Topic` above renders no topic), collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`

The branch is only a topic fallback: the topic comes from an explicit argument first and the branch last, so a run with a topic argument makes no `git branch` call. Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Purpose

External research is mandatory before acting on external facts, and its sources are authoritative and official ones fetched this session. Training data drifts, library APIs change, SEO content farms outrank authoritative sources, and AI synthesis tools repackage the same secondary blogs as "multi-source", so cross-tool consensus, primary-source priority and recency verification are what drive accuracy.

Local counterpart: `/discovery:explore` (what IS in the repo); this skill covers what SHOULD BE. A local folder outside any repository (a vendor install directory) or machine state is this skill's too: read it directly and cite those reads as Tier 0 primaries. For a multi-topic or workflow-driven pass, invoke `/discovery:research-deep` via the Skill tool, which layers tiered execution on this discipline.

## Phases

**Fan out per gap when nesting is available.** When the dispatch prompt says nested spawn is available, follow the per-gap recipe in [context/discipline.md](context/discipline.md). Phase 0 through Phase 4, the queries and the lists each phase must write before the next: [context/phases.md](context/phases.md). Load that file when you are the worker, before the first query.

## Output Format

Present research findings as, and if invoked standalone present them directly, while inside a larger workflow they feed the subsequent planning step:

1. **Summary**. 2-3 sentence answer to the research question, preceded by one line naming any decision the findings leave to the user (e.g. two primary sources conflict, or a gap blocks the answer), or omitted when none. A run with no accepted claim opens instead with `Inconclusive: no claim accepted.` (criterion 14)
2. **Evidence table**. `Claim | Sources (Tier 0/1 entries cite the URL/command fetched THIS turn) | Tier | Tool diversity | Confidence`. A source whose `standing:` is `historical` carries the label historical in its Sources cell, and a flagged claim's Confidence cell reads `HIGH (single source)`
3. **Fetch log**, the written record criteria 6 and 9 are graded against, so it is WRITTEN, not recalled. One entry per fetch PER CLAIM: `Claim | URL or command | artifact-ladder rung | tool used | outcome`, and each accepted claim carries the entry for the rung it came from AND one for every rung above it. **The outcome vocabulary is a parsed schema, not free text**. Five values, three of which look interchangeable and are not, plus the composite changelog entry criterion 6 grades. Write it to the spec in `${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md` ("The fetch log")
4. **Conflicts**. Disagreements between sources (flagged explicitly; primary wins over blog consensus)
5. **Gaps**. Claims below HIGH (criterion 7; `HIGH (single source)` under row 4's flag counts) or below the criterion-4 floor of ≥1 primary + 2 independent corroborators (or a holding `single source` flag), flagged for follow-up; a single-publisher claim is listed under its label (the discipline file's "Single-publisher facts"). A gap asserting absence names the sources checked AND the sources left unchecked, never a bare "not found"
6. **Recency status**. Primary-source age per tool/library claim
7. **Project fit**. How findings align with the consuming project's conventions and stated direction
8. **Outcome gate result**. Pass, or which criterion failed and what was re-run, plus effort and any skipped phases

## Final step: persist artifact for handoff

Write the research output to `<memory_dir>/<slug>/RESEARCH.md`, a memory-tier artifact, never committed, and the authoritative summary of the stage: a fresh session must be able to resume planning reading only it. Destination and slug resolve per the lifecycle artifact protocol ([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)). **No project root** (no git toplevel or project marker, such as a session started in the home directory): an interactive run asks before writing (create under the current directory, or an explicit path); a non-interactive run writes under `${CLAUDE_PLUGIN_DATA}/artifacts/<slug>/` and announces the absolute path. Never create a `.work/` under the home directory unasked.

**`RESEARCH.md` is always an INDEX**, at every size, not only past an overflow threshold. It carries the Task restatement, a one-line abstract per sidecar copied verbatim from that sidecar's header, a section → file + anchor table, and the Next-stage-handoff. The Output Format's content lives in sibling `RESEARCH-<section>.md` sidecars in the same directory, each opening with a machine-readable YAML header so a consumer can grep headers, then read exactly one file.

**One writer per slice.** The index and `research-checklist.md` have fixed names, so two runs writing one slice overwrite each other. When the slice root is occupied, or a parent is running several topics in parallel, **each run writes its whole set into its own sub-slice** `<memory_dir>/<slug>/<topic-slug>/` under the normal filenames and reports the path it used. The parent assigns those sub-slices; a worker never picks its own. Why renaming the index instead is not an option: the artifact-shape file.

**Read [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md) before writing the first sidecar**, the sidecar header and the fetch log are both schemas a verifier parses, and an improvised one silently costs criteria 4, 6, 9, 12 and 13 their evidence. Carry this much into the read: `claims[]` is a LIST, each entry with its own `confidence`, its own target `applies_to`, its own `sources[]` of `{url, tier, pool, measures, role, published, applies_to, standing}`, and its own `inference` and `qualifiers`, plus `subject_pool` on a single-publisher claim; the index records `evidence_use` and `accepted`.

**Intra-task pivot. Delete stale research, don't layer.** If the approach you researched is abandoned mid-task for a different direction *before shipping*, delete the now-stale section and re-run on the new direction; a superseded section makes the planning step plan against a dead approach. Failure modes this skill has actually hit: `${CLAUDE_PLUGIN_ROOT}/skills/research/context/gotchas.md`.

## What this skill does NOT do

- **Does not make decisions**. Presents verified evidence; the planning step (or user) decides
- **Does not write code**. Researches only; execution is a separate step
- **Does not skip phases for "simple" topics**. Task size does not reduce depth; only the Effort table may skip later phases, at the row caller effort or a `breadth=` token selects
- **Does not present training-data knowledge as current fact**. Tier 3 recall must be promoted to Tier 0/1 before claim acceptance

## Spoke paths

The `context/` files write the plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`. Put that path in place of the placeholder before running a command or
writing it into a brief. Those files arrive through the Read tool as plain bytes, so a `${…}` token
in them would reach the Bash tool unsubstituted, and the Bash tool's environment has no
`CLAUDE_PLUGIN_ROOT` to expand it from. Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins-reference#where-each-variable-resolves>, verified
2026-09-29; recheck when that table adds supporting files to where a `${…}` reference resolves.

## Next

- Findings are ready to act on: `/planning:plan`.
- A multi-topic or workflow-driven pass: `/discovery:research-deep`.
- The reasons behind a past decision: `/discovery:trace-intent <subject>`.

## See also

- `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md`. Source tiers, recency gates, broad-topic recipe, effort ceiling over that doubling, falsification recipe, tool-ecosystem fallback, confidence calibration, source-quality red flags, observed failure patterns
