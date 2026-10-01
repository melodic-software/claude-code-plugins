# Upstream source: ClaudeDevs "Reducing cost and improving performance with Claude Platform"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [Lane T1: prompt-cache management](#lane-t1-prompt-cache-management)
- [Lane T2: prompt instruction anti-patterns](#lane-t2-prompt-instruction-anti-patterns)
- [Lane T3: effort calibration](#lane-t3-effort-calibration)
- [Lane T4: API cost optimization and profiling](#lane-t4-api-cost-optimization-and-profiling)
- [Lane M: record and gating meta-decisions](#lane-m-record-and-gating-meta-decisions)
- [Interview queue](#interview-queue)

Provenance record for everything in this marketplace vetted against the 2026-09-08 X Article /
blog post "Reducing cost and improving performance with Claude Platform" by the Claude
Developers account (authors Lance Martin, Brad Abrams, Isabella He, Ben Lehrburger). One
convention, one scoped record, per the pattern [aihero-course.md](aihero-course.md) set: lanes
decide but never implement; every plain ADOPT row points at a filed work item; changes execute
through the normal pipeline.

## Status

Discovery complete (explore + research, both dispatched, gated, and independently verified).
**All five lanes interviewed and decided 2026-09-10**; every row below carries its verdict
(ADOPT / REJECT with reason / TRACK on event / COVERED with evidence), and the accepted
adoptions are implemented on this record's branch (see the interview queue section for the
work list). The three native-overlap verdicts this effort produced (bundled `claude-api`
against `claude-config:audit-instructions`, `evals:methodology`, and `playbooks:fable-5`) are
baked as `## Boundary` sections in those skill bodies with detail in a same-skill reference
file, per the amended native-references convention (1.1.0: a non-`defer` extraction-evidence
row lands together with its Boundary section). Open TRACK triggers: the anthropics/skills repo
or the claude-api docs page gaining hillclimb/build-eval; a Console-side check confirming the
cache-diagnostics UI; a second real need for API-cost tooling in this marketplace.

## Source and verification

- Main docs page covering the article's topic:
  [Optimizing for cost and intelligence](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence).
  The article itself is never a pointer: (correlate with `https://x.com/ClaudeDevs/status/2097369738968195513`, 2026-09-08)
  and its mirror (correlate with `https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform`).
  Content parity between the two confirmed 2026-09-09; the blog carries the seven figures.
- Reply-chain coverage is a bounded gap: no converter reachable from the discovery session
  could enumerate X replies (Thread Reader has no unroll of this post), and a web search
  surfaced no official follow-up posts. Checked: threadreaderapp.com, web search. Unchecked:
  the live X reply timeline (needs X auth).
- Our verification ran 2026-09-09 against live primaries (a 24-row bounded ledger, coverage
  gate exit 0): every prompt-caching, effort, mid-conversation-system-message, batching, and
  Admin API mechanism the article names was checked against the platform docs page each row
  points at, and the skill-behavior rows were checked source-as-spec against the
  anthropics/skills clone (HEAD `41bbe19`, 2026-09-03) plus the skill bundled inside Claude
  Code 2.1.263.
- Five verification findings qualify adoption everywhere below:
  1. **hillclimb repo lag.** Our extraction found `/claude-api hillclimb` (and `build-eval`) in
     the bundled skill inside the Claude Code binary, and an exhaustive grep found them absent
     from the public anthropics/skills repo the article links (HEAD 2026-09-03) and from the
     skill's platform-docs page. A reader following the article's GitHub link will not find
     them. Pointer: our binary extraction and clone grep, recorded in the claude-api row of
     [`docs/native-surfaces/records.json`](../native-surfaces/records.json), and [In Claude Code (bundled)](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill#in-claude-code-bundled).
     As of: 2026-09-09. Recheck trigger: the repo or docs page gains the subcommands.
  2. **Claude Console diagnostics UI unverified.** The API half of the cache-diagnostics topic
     is verified against
     [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types);
     no fetched doc covers the Console request-comparison UI the article shows. Checked:
     cache-diagnostics doc, usage-cost-api doc, two web searches. Unchecked: the Console
     product itself (needs a login). As of: 2026-09-09. Recheck trigger: a docs page starts
     covering the Console request-comparison UI, or someone checks the Console itself.
  3. **Benchmark numbers are vendor-internal.** The article's benchmark figures are single-pool
     Anthropic measurements with no published artifact to reproduce from, so no figure is
     recorded here. Posture recommended by the research run: adopt mechanisms, cite numbers
     only as vendor-reported, read at the source.
  4. **Release-status boundaries.** Every adopted line touching per-message effort, the cache
     diagnostics API, or mid-conversation system messages names the feature's release status and
     the platforms and models it is limited to, as read at the pointer when the line is written,
     never from memory and never assuming beta. Re-read 2026-10-01: the three features no longer
     share one status, so a line that calls all three beta is stale and is corrected when next
     touched.
     - **Pointer**: for each feature's status and limits, see
       [Per-message effort (beta)](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta),
       [Cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics)
       and
       [Mid-conversation system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages)
       (on both pages the status and availability notes sit under the page title, in no section
       of their own).
     - **As of**: 2026-10-01
     - **Recheck trigger**: any of the three pages changes the feature's release status, its
       supported platforms, or its supported models.
  5. **Corroboration verdict (fresh-context verifier, 2026-09-09).** Every accepted row is
     HIGH confidence and five live spot checks matched current sources; four rows rest on a
     single evidence pool because no independent second pool exists publicly:
     automatic-caching breakpoint movement (docs plus a restatement page; substance
     re-confirmed live), cost-optimize behavior (skill source only; the skill's docs page does
     not document the command), hillclimb-bundled and hillclimb-absent (binary extraction and
     an exhaustive clone grep, both direct observations). Rows built on these carry the
     qualification rather than a second citation.

## Row schema

Each row is an [upstream-drift](../conventions/upstream-drift/README.md#required-parts) record.
**Topic** names the article's practice in our words; **Ours** and **Verdict** are our decision
and its reasoning; **Pointer** is the exact docs section, or our own probe where no docs page
covers the topic; **As of** is when the pointer was last read. No row restates the article or
the page. Columns:

| Topic | Ours | Verdict | Pointer | As of |

Shared recheck trigger for every row: a re-fetch of the row's pointer no longer supports the
verdict. A TRACK verdict names its own trigger in its cell. "Explore evidence" paths were
independently re-verified against the repo on 2026-09-09.

## Lane T1: prompt-cache management

Repo coverage today is Claude-Code-session-side doctrine only: the PLUGIN-PHILOSOPHY effort
cache caveat, `audit-instructions` criteria row I17-b, the playbooks fable-5
`context/orchestration.md` subagent-TTL records, `context-budget` (startup prefix cost),
`claude-ops:observability` (cacheRead vs cacheCreation from local OTEL), and the
`extract-ssot` API-side byte-identical-prefix record
(`plugins/docs-hygiene/skills/extract-ssot/context/anti-patterns.md`). API-application cache
authoring guidance has no incumbent.

Decided at interview, 2026-09-10: the adopted API-side practices land as **one new
prompt-caching reference chapter in the playbooks plugin**, beside the model-adaptation
chapters: pointer records citing each docs anchor, beta qualifiers carried, session-side
coverage cross-referenced. One work item covers the chapter.

| Topic | Ours | Verdict | Pointer | As of |
|---|---|---|---|---|
| Cache hit-rate monitoring and miss diagnosis | `claude-ops:observability` covers Claude Code sessions only | ADOPT API half (chapter row, beta-qualified) + TRACK Console half; also ADOPT one boundary-pointer line in the observability skill's cache-health context (decided 2026-09-10). Console UI unverified (finding 2); TRACK trigger: a Console-access check or a docs page confirming the request-comparison UI | [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types) | 2026-09-09 |
| Prefix stability and request layout | `extract-ssot` anti-patterns record carries the byte-identical-prefix rule (as of 2026-08-04); no authoring-rule surface for request-building code | ADOPT (chapter rows; decided 2026-09-10) | [Structuring your prompt](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#structuring-your-prompt) | 2026-09-09 |
| Deferred loading of rarely used tools | `context-budget` levers.json engages defer_loading for Claude Code MCP tools only | ADOPT (chapter row; decided 2026-09-10) | [defer_loading and cache preservation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching#defer-loading-and-cache-preservation) | 2026-09-09 |
| System-prompt updates as mid-conversation messages | No coverage | ADOPT (chapter row; GA and model-list boundary carried; decided 2026-09-10) | [When to use a mid-conversation system message](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#when-to-use-a-mid-conversation-system-message) | 2026-09-09 |
| Timing model and effort changes to cache breaks (compaction) | PLUGIN-PHILOSOPHY cache caveat carries the session-side version | COVERED session-side; API-side sentence joins the chapter (decided 2026-09-10). No docs page covers this timing practice as of 2026-09-09 (correlate with Cognition's devin-fusion post, 2026-06-29) | [What invalidates the cache](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache) | 2026-09-09 |
| Breakpoint placement as a conversation grows | No coverage | ADOPT (chapter row; decided 2026-09-10) | [Automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) | 2026-09-09 |
| Cache pre-warming at session start | No coverage | ADOPT (chapter row; decided 2026-09-10); the chapter points at the request shapes pre-warming rejects rather than listing them | [Pre-warming the cache](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#pre-warming-the-cache) and the bundled skill source | 2026-09-09 |
| Cache TTL across long tool calls | fable-5 `orchestration.md:97` carries the Claude Code subagent version (as of 2026-09-06) | COVERED session-side; API-side rows join the chapter (decided 2026-09-10) | [1-hour cache duration](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration) and [Prompt caching pricing](https://platform.claude.com/docs/en/about-claude/pricing#prompt-caching) | 2026-09-09 |

## Lane T2: prompt instruction anti-patterns

**The repo has already executed this lane's remedy.** A fleet-wide `/claude-api prompt-audit`
run (Claude Code 2.1.258 against Fable 5.1) covered 74 plugins, 241 skills, 798 files, about
115k lines; 805 findings applied, 207 withheld, 694 files changed
(`docs/specs/prompt-audit-skills-2026-09.md`, ADR-0028). ADR-0028 makes it a repeating lane
per model change. The `claude-config:audit-instructions` criteria catalog maps one-to-one onto
the six anti-pattern families the article names:

| Anti-pattern family | Catalog row(s) in `audit-instructions/reference/criteria.md` |
|---|---|
| Verification rituals | I8-a, I8-b |
| Emphasis boosters | I28-a, I6 |
| Mandatory procedures / scratchpads | I8-c, I8-e, I10 |
| Stale few-shot examples | I9 |
| Contradictory rules | I15 plus `conflict-scan.sh` |
| Dated configuration | I17 family, I25, I21 |

Native-first gate row, decided at interview 2026-09-10: the (bundled claude-api,
`claude-config:audit-instructions`) pair is recorded **complementary** in
`docs/native-surfaces/records.json` with a composite posture: wrap or point to the bundled
subcommand where it fits the use case, run our own processes where they fit; no on-paper
routing restriction. The verdict is baked where the model reads it: a `## Boundary, the
bundled claude-api skill` section in the `audit-instructions` body (routing, mutation gate,
availability rule) with its records in
`plugins/claude-config/skills/audit-instructions/reference/bundled-claude-api.md`. Recheck
fires with the store row's trigger (subcommand set changes, or the public repo / docs page
gains hillclimb).

| Topic | Ours | Verdict | Pointer | As of |
|---|---|---|---|---|
| Instruction anti-patterns on current models | `audit-instructions` catalog + executed fleet-wide prompt-audit | COVERED (Claude Code surfaces; decided 2026-09-10). Explore mapping re-verified against criteria.md TOC and rows; ADR-0028's repeat-per-model-change lane is the standing remedy | [Audit prompts against the current model](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#audit-prompts-against-the-current-model) and the skill's `prompt-audit.md` | 2026-09-09 |
| Prompt audit of application-code prompts | No repo skill audits app-code prompts; `audit-instructions` scope is deliberately Claude Code surfaces | REJECT scope-widening (decided 2026-09-10). The bundled prompt-audit owns the app-code surface; the skill's scope boundary is deliberate. Our source-as-spec read found request-building code in its Step 0-1 inventory. Revisit only if marketplace-native app-code coverage is wanted later | [Claude API skill](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill#what-the-skill-provides) and the skill's `prompt-audit.md` | 2026-09-09 |
| Manual thinking budgets on newer models | I17 family covers the instruction-surface version | COVERED (decided 2026-09-10) | [Configuring thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#configuring-thinking) | 2026-09-09 |

## Lane T3: effort calibration

Mostly covered: PLUGIN-PHILOSOPHY "Effort tiers" lane rules, catalog rows I21/I22/I27,
model-adaptation chapters (opus-5 "move down liberally", fable-5-1 "recall at low effort"),
`${CLAUDE_EFFORT}` consumed by 7 skills, and every named agent's effort pin, `high` or `medium`
(see the pinned-agents record under [Effort tiers](../plugin-philosophy.md#effort-tiers) and the
[Effort floor](../plugin-philosophy.md#effort-floor)). Missing: cross-model economics and sweep
tooling.

| Topic | Ours | Verdict | Pointer | As of |
|---|---|---|---|---|
| Effort miscalibration in both directions | PLUGIN-PHILOSOPHY Effort tiers; opus-5 chapter overthinking guidance; fable-5-1 low-effort recall caveat | COVERED, plus a sharpening ADOPT (decided 2026-09-10). Explore evidence re-verified 2026-09-09. Work item: fold the article's two sharpest phrasings on miscalibration, in our words, into the existing surfaces | [How effort works](https://platform.claude.com/docs/en/build-with-claude/effort#how-effort-works) | 2026-09-09 |
| A stronger model at lower effort | Nowhere; adaptation chapters deliberately carry no pricing | ADOPT (decided 2026-09-10). Land as a pricing-free section in the fable-5-1 model-adaptation chapter plus a one-line pointer in PLUGIN-PHILOSOPHY Effort tiers; numbers cited vendor-reported; pricing stays pointer-resolved through the claude-api skill | [Compare models on cost per task](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#compare-models-on-cost-per-task) and [Model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing) | 2026-09-09 |
| Effort sweeps on a non-saturated eval | `evals` plugin has zero effort content | ADOPT (decided 2026-09-10). Land as an effort-axis note in the evals plugin citing the bundled hillclimb per the Lane M posture (bundled-only, public-repo lag noted) | [Tune effort](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#tune-effort) | 2026-09-09 |
| Effort changes mid-conversation and the cache | PLUGIN-PHILOSOPHY cache caveat + criteria I17-b carry the session-side version | COVERED session-side (decided 2026-09-10). The API-side model list is read at the pointer only inside whatever T1/T3 adoptions get written, per the Lane M beta posture; no separate surface | [Per-message effort (beta)](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta) | 2026-09-09 |

## Lane T4: API cost optimization and profiling

Thin: local Claude Code cost telemetry (`claude-ops:observability`), startup-prefix
measurement (`context-budget`), and the adjacent `rate-limit-guard` (subscription windows, not
cost). Batch API, output bounding as a cost lever, and the usage/cost Admin API are uncovered.
`cost-optimize` and `hillclimb` have zero in-repo references.

| Topic | Ours | Verdict | Pointer | As of |
|---|---|---|---|---|
| Spend profiling with the bundled cost-optimize | No incumbent for API-application profiling | TRACK on the bundled cost-optimize, plus one mention in the new playbooks chapter as the automation for its levers (decided 2026-09-10). Our source-as-spec read found it proposes rather than silently applies. New-plugin question deferred to a second real need | Our read of the bundled skill source (`shared/cost-optimization.md`); no docs page covers the command | 2026-09-09 |
| Model and effort search with the bundled hillclimb | No incumbent; `evals` owns eval design without a cost axis | Cited per the Lane M posture: bundled-only, public-repo lag noted (decided 2026-09-10); the evals effort-axis note carries the citation. Recheck: the repo or docs page gains the subcommand | Our extraction of the bundled skill source from the binary (finding 1); [In Claude Code (bundled)](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill#in-claude-code-bundled) | 2026-09-09 |
| Batching unattended work | Absent (sole mention is a routines.md disclaimer) | ADOPT (chapter row; decided 2026-09-10) | [Batch processing pricing](https://platform.claude.com/docs/en/about-claude/pricing#batch-processing) | 2026-09-09 |
| Output bounding as a cost lever | In tension with prompt-audit Group 1f, which removes numeric output ceilings from skill bodies | Recorded scope-disjoint (decided 2026-09-10): output bounding is an API-request cost lever, never a skill-body instruction pattern; one sentence in the chapter says so. Tension identified by explore, 2026-09-09 | [Set budgets and output caps](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#set-budgets-and-output-caps) | 2026-09-09 |
| Org spend profiling through the Admin API | Absent | ADOPT (chapter row; decided 2026-09-10) | [Usage and Cost API: Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api#cost-api) | 2026-09-09 |

## Lane M: record and gating meta-decisions

Decided at interview, 2026-09-10:

| Question | Verdict | Reasoning, basis, as-of |
|---|---|---|
| Record shape | DECIDED: keep this file's shape. Only the row-schema FORMAT is borrowed from aihero-course.md (per-row records, verdict vocabulary); this source is unrelated to AI Hero and this record stands alone | Owner interview, 2026-09-10 |
| Native-overlap gate before any new skill: the article's guidance IS the bundled claude-api skill | DECIDED: run `/claude-ops:audit-native-overlap` against the four topics first and record its verdicts as gate rows; adoption scope is NOT pre-restricted on paper. The owner receives full information per topic and decides at each lane interview. Amended 2026-09-11: a registry row alone is not the deliverable; each non-`defer` verdict lands as a `## Boundary` section in the skill body with detail in a same-skill reference file, and the native-references convention (1.1.0) now requires the pair | Owner interview, 2026-09-10 and 2026-09-11; PLUGIN-PHILOSOPHY Native-first section; ADR-0028 precedent |
| Vendor-internal numbers and beta features | DECIDED: adopt mechanisms only; cite figures as vendor-reported and unreproduced; every adopted line touching a beta feature carries its beta qualifier and GA/model-list boundary | Owner interview, 2026-09-10 |
| Citing hillclimb while the public repo lags | DECIDED: cite it as a bundled Claude Code command with an upstream-drift record noting the public-repo lag; recheck trigger fires when the anthropics/skills repo or the skill's docs page gains the subcommand | Owner interview, 2026-09-10 |

## Interview queue

All five lanes interviewed and decided 2026-09-10, in order M, T2, T3, T1, T4; verdicts are
in each lane's section above. Execution decision: implement the accepted adoptions on this
branch in this effort (one branch, one draft PR). All five items below are implemented on this
branch (playbooks 0.11.0, evals 0.2.3, claude-ops 0.48.0, claude-config 0.42.0; git history
of this file's branch records the commits):

1. New playbooks prompt-caching reference chapter (T1 chapter rows + T4 Batch/Admin/
   cost-optimize-mention/output-bounding rows), beta qualifiers carried.
2. fable-5-1 model-adaptation chapter: pricing-free cross-model economics section, plus a
   one-line pointer in PLUGIN-PHILOSOPHY Effort tiers (T3).
3. evals plugin effort-axis note citing the bundled hillclimb (T3).
4. Sharpening pass folding the article's two phrasings into the existing effort surfaces
   (T3).
5. Observability cache-health boundary pointer to the cache diagnostics API (T1).
