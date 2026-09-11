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

- Post: `https://x.com/ClaudeDevs/status/2097369738968195513` (2026-09-08). Canonical mirror:
  `https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform`.
  Content parity between the two confirmed 2026-09-09; the blog carries the seven figures.
- Reply-chain coverage is a bounded gap: no converter reachable from the discovery session
  could enumerate X replies (Thread Reader has no unroll of this post), and a web search
  surfaced no official follow-up posts. Checked: threadreaderapp.com, web search. Unchecked:
  the live X reply timeline (needs X auth).
- Claim verification ran 2026-09-09 against live primaries (a 24-row bounded ledger, coverage
  gate exit 0): every prompt-caching, effort, mid-conversation-system-message, batching, and
  Admin API mechanics claim in the article verified against the platform docs pages the
  article itself links, and the skill-behavior claims verified source-as-spec from the
  anthropics/skills clone (HEAD `41bbe19`, 2026-09-03) plus the skill bundled inside Claude
  Code 2.1.263. Recheck trigger for every row below: divergence at re-fetch of the named
  basis.
- Three verification findings qualify adoption everywhere below:
  1. **hillclimb repo lag.** `/claude-api hillclimb` (and `build-eval`) ship in the bundled
     skill inside the Claude Code binary but are absent from the public anthropics/skills repo
     the article links (HEAD 2026-09-03) and from the skill's platform-docs page. A reader
     following the article's GitHub link will not find them. Recheck: the repo or docs page
     gains the subcommands.
  2. **Claude Console diagnostics UI unverified.** The API half of the cache-diagnostics claim
     is fully verified (four `*_changed` miss reasons); no fetched doc describes the Console
     request-comparison UI in the article's Figure 1. Checked: cache-diagnostics doc,
     usage-cost-api doc, two web searches. Unchecked: the Console product itself (needs a
     login).
  3. **Benchmark numbers are vendor-internal.** Figures 3 to 7 (14.6 percent cost cut, +5.3
     points, FrontierCode Diamond, CursorBench 3.2, the four cost-optimize benchmarks) are
     single-pool Anthropic measurements with no published artifact to reproduce from. Posture
     recommended by the research run: adopt mechanisms, cite numbers only as vendor-reported.
  4. **Beta boundaries.** Per-message effort changes (Fable 5.1, Mythos 5.1, Opus 5), the
     cache diagnostics API, and turn-scoped system messages are betas with headers; plain
     mid-conversation system messages are GA on six models (not Sonnet 5). Adopted guidance
     carries the qualifiers.
  5. **Corroboration verdict (fresh-context verifier, 2026-09-09).** Every accepted claim is
     HIGH confidence and five live spot checks matched current sources verbatim; four claims
     rest on a single evidence pool because no independent second pool exists publicly:
     automatic-caching breakpoint movement (docs plus a restatement page; substance
     re-confirmed live), cost-optimize behavior (skill source only; the skill's docs page does
     not document the command), hillclimb-bundled and hillclimb-absent (binary extraction and
     an exhaustive clone grep, both direct observations). Rows built on these carry the
     qualification rather than a second citation.

## Row schema

Each row is a four-part record per
[docs/conventions/upstream-drift/README.md](../conventions/upstream-drift/README.md): the
claim, the basis it was derived against, the as-of date, and a recheck trigger. Columns:

| Article claim / practice | Ours | Verdict | Reasoning, basis, as-of |

Shared basis shorthand used below: "article" is the source snapshot above; "verified" means
the 2026-09-09 research run confirmed the claim against the named primary; explore evidence
paths were independently re-verified against the repo the same day.

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
chapters: four-part pointer rows citing each docs anchor, beta qualifiers carried,
session-side coverage cross-referenced. One work item covers the chapter.

| Article claim / practice | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Monitor cache hit rate; diagnose misses via the cache diagnostics API (miss reasons: messages / system / tools / model changed) | `claude-ops:observability` covers Claude Code sessions only | ADOPT API half (chapter row, beta-qualified) + TRACK Console half; also ADOPT one boundary-pointer line in the observability skill's cache-health context (decided 2026-09-10) | Verified against `platform.claude.com/docs/en/build-with-claude/cache-diagnostics`, 2026-09-09. Console UI unverified (finding 2); TRACK trigger: a Console-access check or a docs page confirming the request-comparison UI |
| Keep volatile values (timestamps, IDs) out of the prefix; stable-first request layout; tool definitions render first and any change breaks cache | `extract-ssot` anti-patterns record states the byte-identical-prefix rule (verified 2026-08-04); no authoring-rule surface for request-building code | ADOPT (chapter rows; decided 2026-09-10) | Verified against `prompt-caching#structuring-your-prompt`, 2026-09-09 |
| defer_loading rarely used tools; tool search appends them without breaking cache | `context-budget` levers.json engages defer_loading for Claude Code MCP tools only | ADOPT (chapter row; decided 2026-09-10) | Verified against `tool-use-with-prompt-caching#defer-loading-and-cache-preservation`, 2026-09-09 |
| Apply system-prompt updates as mid-conversation messages (cache-preserving; certain models) | No coverage | ADOPT (chapter row; GA six-model list, not Sonnet 5; decided 2026-09-10) | Verified against `mid-conversation-system-messages`, 2026-09-09 |
| Batch model/effort changes into already-broken-cache moments (compaction) | PLUGIN-PHILOSOPHY cache caveat carries the session-side version | COVERED session-side; API-side sentence joins the chapter (decided 2026-09-10) | Article; corroborated by Cognition devin-fusion post, 2026-06-29 |
| Move breakpoints as conversation grows; automatic caching pins the last cacheable block | No coverage | ADOPT (chapter row; decided 2026-09-10) | Verified against `prompt-caching#automatic-caching`, 2026-09-09 |
| Pre-warm with `max_tokens: 0` plus explicit breakpoint at session start | No coverage | ADOPT (chapter row; decided 2026-09-10) | Verified against prompt-caching doc and skill source, 2026-09-09; the rejection list (streaming, extended thinking, structured outputs, forced tool_choice, batches) rides along |
| 5-minute TTL counts from request start; long tool calls expire the parent cache; use 1-hour TTL (2x write rate) | fable-5 `orchestration.md:97` carries the Claude Code subagent version (re-verified 2026-09-06) | COVERED session-side; API-side rows join the chapter (decided 2026-09-10) | Verified against `prompt-caching#ttl-support` and pricing page, 2026-09-09 |

## Lane T2: prompt instruction anti-patterns

**The repo has already executed this lane's remedy.** A fleet-wide `/claude-api prompt-audit`
run (Claude Code 2.1.258 against Fable 5.1) covered 74 plugins, 241 skills, 798 files, about
115k lines; 805 findings applied, 207 withheld, 694 files changed
(`docs/specs/prompt-audit-skills-2026-09.md`, ADR-0028). ADR-0028 makes it a repeating lane
per model change. The `claude-config:audit-instructions` criteria catalog maps one-to-one onto
the article's six anti-pattern families:

| Article anti-pattern | Catalog row(s) in `audit-instructions/reference/criteria.md` |
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
availability rule) with the four-part records in
`plugins/claude-config/skills/audit-instructions/reference/bundled-claude-api.md`. Recheck
fires with the store row's trigger (subcommand set changes, or the public repo / docs page
gains hillclimb).

| Article claim / practice | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Six anti-pattern families hobble frontier models; audit and remove them | `audit-instructions` catalog + executed fleet-wide prompt-audit | COVERED (Claude Code surfaces; decided 2026-09-10) | Explore mapping re-verified against criteria.md TOC and rows, 2026-09-09; anti-patterns verified documented in `optimizing-for-cost-and-intelligence` and skill `prompt-audit.md`, 2026-09-09; ADR-0028's repeat-per-model-change lane is the standing remedy |
| prompt-audit also covers prompts in application code calling the Claude API | No repo skill audits app-code prompts; `audit-instructions` scope is deliberately Claude Code surfaces | REJECT scope-widening (decided 2026-09-10) | The bundled prompt-audit owns the app-code surface; the skill's scope boundary is deliberate. prompt-audit.md Step 0-1 inventory includes request-building code, verified source-as-spec 2026-09-09. Revisit only if marketplace-native app-code coverage is wanted later |
| Manual thinking budgets rejected outright by the API on newer models | I17 family covers the instruction-surface version | COVERED (decided 2026-09-10) | Verified (400 rejection documented) 2026-09-09 |

## Lane T3: effort calibration

Mostly covered: PLUGIN-PHILOSOPHY "Effort tiers" lane rules, catalog rows I21/I22/I27,
model-adaptation chapters (opus-5 "move down liberally", fable-5-1 "recall at low effort"),
`${CLAUDE_EFFORT}` consumed by 7 skills, 13 agents pinned `effort: high`. Missing: cross-model
economics and sweep tooling.

| Article claim / practice | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Effort miscalibration cuts both ways (over-thinking degrades quality; under-thinking answers from partial evidence) | PLUGIN-PHILOSOPHY Effort tiers; opus-5 chapter overthinking guidance; fable-5-1 low-effort recall caveat | COVERED, plus a sharpening ADOPT (decided 2026-09-10) | Explore evidence re-verified 2026-09-09; effort semantics verified against the effort doc. Work item: fold the article's sharpest phrasings (deliberation only helps while there is evidence to find; the answer looks finished but is built on partial information) into the existing surfaces |
| Test stronger models at lower effort (Fable 5.1 low matches Fable 5 high at a third of the cost; cache reads $0.25/M vs $1.00/M) | Nowhere; adaptation chapters deliberately carry no pricing | ADOPT (decided 2026-09-10) | Land as a pricing-free section in the fable-5-1 model-adaptation chapter plus a one-line pointer in PLUGIN-PHILOSOPHY Effort tiers; numbers cited vendor-reported; pricing stays pointer-resolved through the claude-api skill. Pricing verified against the pricing page and API release notes 2026-09-01 entry, fetched 2026-09-09 |
| Sweep effort levels on a non-saturated eval; flat curve means not thinking-bound | `evals` plugin has zero effort content | ADOPT (decided 2026-09-10) | Land as an effort-axis note in the evals plugin citing the bundled hillclimb per the Lane M posture (bundled-only, public-repo lag noted). Verified against `optimizing-for-cost-and-intelligence#tune-effort`, 2026-09-09 |
| Only select models change effort mid-conversation without breaking cache | PLUGIN-PHILOSOPHY cache caveat + criteria I17-b carry the session-side version | COVERED session-side (decided 2026-09-10) | The API-side model list (Fable 5.1, Mythos 5.1, Opus 5, beta header; Fable 5 returns 400) lands only inside whatever T1/T3 adoptions get written, per the Lane M beta posture; no separate surface. Verified against `effort#change-effort-mid-conversation-beta`, 2026-09-09 |

## Lane T4: API cost optimization and profiling

Thin: local Claude Code cost telemetry (`claude-ops:observability`), startup-prefix
measurement (`context-budget`), and the adjacent `rate-limit-guard` (subscription windows, not
cost). Batch API, output bounding as a cost lever, and the usage/cost Admin API are uncovered.
`cost-optimize` and `hillclimb` have zero in-repo references.

| Article claim / practice | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| cost-optimize profiles spend (Admin API, else logged `usage` objects, else code estimate), ranks levers, measures against an eval | No incumbent for API-application profiling | TRACK on the bundled cost-optimize, plus one mention in the new playbooks chapter as the automation for its levers (decided 2026-09-10) | Verified source-as-spec (`shared/cost-optimization.md`), 2026-09-09; nuance: it proposes rather than silently applies. New-plugin question deferred to a second real need |
| hillclimb searches cost/performance over models and effort with train/test split | No incumbent; `evals` owns eval design without a cost axis | Cited per the Lane M posture: bundled-only, public-repo lag noted (decided 2026-09-10); the evals effort-axis note carries the citation | Verified from the bundled skill source extracted from the binary, 2026-09-09; absent from public repo HEAD. Recheck: the repo or docs page gains the subcommand |
| Batch unattended work (50 percent discount, stacks with cache multipliers) | Absent (sole mention is a routines.md disclaimer) | ADOPT (chapter row; decided 2026-09-10) | Verified against the pricing page batch section, 2026-09-09 |
| Bound output to save cost (SWE-bench case: concise-output constraint) | In tension with prompt-audit Group 1f, which removes numeric output ceilings from skill bodies | Recorded scope-disjoint (decided 2026-09-10): output bounding is an API-request cost lever, never a skill-body instruction pattern; one sentence in the chapter says so | Article; tension identified by explore, 2026-09-09 |
| Usage and Cost Admin API for org spend profiling | Absent | ADOPT (chapter row; decided 2026-09-10) | Verified against `manage-claude/usage-cost-api`, 2026-09-09 |

## Lane M: record and gating meta-decisions

Decided at interview, 2026-09-10:

| Question | Verdict | Reasoning, basis, as-of |
|---|---|---|
| Record shape | DECIDED: keep this file's shape. Only the row-schema FORMAT is borrowed from aihero-course.md (four-part rows, verdict vocabulary); this source is unrelated to AI Hero and this record stands alone | Owner interview, 2026-09-10 |
| Native-overlap gate before any new skill: the article's guidance IS the bundled claude-api skill | DECIDED: run `/claude-ops:audit-native-overlap` against the four topics first and record its verdicts as gate rows; adoption scope is NOT pre-restricted on paper. The owner receives full information per topic and decides at each lane interview. Amended 2026-09-11: a registry row alone is not the deliverable; each non-`defer` verdict lands as a `## Boundary` section in the skill body with detail in a same-skill reference file, and the native-references convention (1.1.0) now requires the pair | Owner interview, 2026-09-10 and 2026-09-11; PLUGIN-PHILOSOPHY Native-first section; ADR-0028 precedent |
| Vendor-internal numbers and beta features | DECIDED: adopt mechanisms only; cite figures as vendor-reported and unreproduced; every adopted line touching a beta feature carries its beta qualifier and GA/model-list boundary | Owner interview, 2026-09-10 |
| Citing hillclimb while the public repo lags | DECIDED: cite it as a bundled Claude Code command with a four-part record noting the public-repo lag; recheck trigger fires when the anthropics/skills repo or the skill's docs page gains the subcommand | Owner interview, 2026-09-10 |

## Interview queue

All five lanes interviewed and decided 2026-09-10, in order M, T2, T3, T1, T4; verdicts are
in each lane's section above. Execution decision: implement the accepted adoptions on this
branch in this effort (one branch, one draft PR). All five items below are implemented on this
branch (playbooks 0.10.0, evals 0.2.3, claude-ops 0.48.0, claude-config 0.42.0; git history
of this file's branch records the commits):

1. New playbooks prompt-caching reference chapter (T1 chapter rows + T4 Batch/Admin/
   cost-optimize-mention/output-bounding rows), beta qualifiers carried.
2. fable-5-1 model-adaptation chapter: pricing-free cross-model economics section, plus a
   one-line pointer in PLUGIN-PHILOSOPHY Effort tiers (T3).
3. evals plugin effort-axis note citing the bundled hillclimb (T3).
4. Sharpening pass folding the article's two phrasings into the existing effort surfaces
   (T3).
5. Observability cache-health boundary pointer to the cache diagnostics API (T1).
