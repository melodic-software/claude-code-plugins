# Upstream source: Anthropic posts on source control, CI and SDLC throughput

## Contents

- [Sources](#sources)
- [Attribution table](#attribution-table)
- [Figures the talk shows](#figures-the-talk-shows)
- [Owner decisions handed on](#owner-decisions-handed-on)
- [License notice](#license-notice)

This page records what this repository takes from, adapts, already has, or rejects in three
Anthropic posts that Lydia Hallie's talk
[Rethinking Claude Code best practices](https://www.youtube.com/watch?v=vlfCjWuv4es) cites or leans
on. Rows hold our decisions and our own descriptions of each idea, under the upstream-drift
convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe); read
upstream at each row's link for what it says. This record changes no workflow or skill: a `take`
or `adapt` that would change the merge lane is listed under
[Owner decisions handed on](#owner-decisions-handed-on).

## Sources

All three were fetched and read on 2026-11-12. No docs page covers these topics, so each post is
the correlate note, not a docs pointer.

- **S** [Redesigning source control at Anthropic](https://www.anthropic.com/research/redesigning-source-control)
  (published 2026-10-13, modified 2026-10-20 per the page's metadata), the post the talk cites.
  - **Pointer**: when a decision here rests on how Anthropic built or runs its own source control,
    fetch [What we learned building Scion](https://www.anthropic.com/research/redesigning-source-control#what-we-learned-building-scion)
    live; no docs page covers agent-scale source control.
- **C** [Agentic coding is straining CI](https://claude.com/resources/articles/agentic-coding-is-straining-ci-heres-how-we-scaled-test-impact-analysis-at-anthropic)
  (published 2026-09-14), the CI companion piece the first post's series links.
  - **Pointer**: when a decision here rests on Anthropic's test selection service, fetch
    [The test impact analysis architecture](https://claude.com/resources/articles/agentic-coding-is-straining-ci-heres-how-we-scaled-test-impact-analysis-at-anthropic#the-test-impact-analysis-architecture)
    live; no docs page covers it.
- **R** [How Anthropic secures its AI-native software development lifecycle](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle)
  (published 2026-07-21), linked from the CI article.
  - **Pointer**: when a decision here rests on Anthropic's risk tiers or approval sampling, fetch
    [Test (CI)](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#test-ci)
    and [Governance](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#governance)
    live; no docs page covers them.

**Limit on transfer (S11).** The source-control post says its design fits only very large
monorepos (a vast engineering staff or large agent fleets) and is no general replacement
for git; see its
[Contributing to the wider ecosystem](https://www.anthropic.com/research/redesigning-source-control#contributing-to-the-wider-ecosystem)
section. Every row about Scion's own machinery is judged against that limit: this repository runs
on git and GitHub at a volume far below it.

## Attribution table

**Stated**: the upstream gives this problem where the label's link points. **Inference**: we
derived it from the mechanism. Disposition is `take`, `adapt`, `already have` or `reject`, with the
reason. Rows S1 to S11 come from post S, C1 to C4 from post C, R1 to R8 from post R.

| Idea (link) | What it does | Upstream problem, motivation, goal | Our problem | Disposition |
|---|---|---|---|---|
| S1 [Always-online clients, server-side commits](https://www.anthropic.com/research/redesigning-source-control#principles-for-agent-scale-source-control) | Moves history, blame, merges and commit creation to a central service; the client keeps a bounded cache. | Git's full-copy model stopped scaling once almost every client was an online agent or job. **Stated** ([source](https://www.anthropic.com/research/redesigning-source-control#growing-our-monorepo)) | none: one git repository on GitHub, cloned per job | **reject:** S11; our clones are not a measured bottleneck. |
| S2 [Changesets and derived data](https://www.anthropic.com/research/redesigning-source-control#data-structures) | Stores each change as a list of touched files and computes blame, path history and ancestry indexes from it, eagerly or lazily per type. | Commit cost must track change size, not repository size, to accept a very high write rate. **Stated** ([source](https://www.anthropic.com/research/redesigning-source-control#principles-for-agent-scale-source-control)) | none | **reject:** S11. |
| S3 [Tiered content-addressed caches](https://www.anthropic.com/research/redesigning-source-control#scaling-scion) | Node daemons fetch immutable trees and blobs through regional caches, falling back to authoritative servers. | Checkout traffic for CI at their volume could not be served by git mirrors. **Stated** ([source](https://www.anthropic.com/research/redesigning-source-control#growing-our-monorepo)) | none | **reject:** S11. |
| S4 [Source-control queries over an API](https://www.anthropic.com/research/redesigning-source-control#principles-for-agent-scale-source-control) | Lets CI jobs and tools ask history or diff questions without a local checkout. | Keeping a checkout only to answer a metadata question was a CI burden. **Stated** ([source](https://www.anthropic.com/research/redesigning-source-control#scaling-scion)) | Partly: lane gates already read pull-request state through the GitHub REST and GraphQL APIs ([pr-pipeline README, The pr-merge lane](../conventions/pr-pipeline/README.md#the-pr-merge-lane)) | **already have:** the GitHub API is our query surface; nothing to build. |
| S5 [Post-merge testing instead of a merge lock](https://www.anthropic.com/research/redesigning-source-control#what-we-learned-building-scion) | Lets changes merge concurrently without a repository-wide lock, then catches breakage with tests run after the merge and before deploy; agents repair the conflicts that follow. | At thousands of merges per hour a serialized queue cannot keep up. **Stated** (same section) | Our merge queue tests each pull request against the base plus the entries ahead of it, up to five built at once and `merge.max-in-flight: 11` lane merges (`docs/conventions/pr-pipeline.yaml` `merge:` block); the ruleset's up-to-date rule is off (`strict_required_status_checks_policy: false`). A full run on `main` follows each merge, and red-main pins a culprit and plans a revert ([Red main](../conventions/pr-pipeline/README.md#red-main)) | **already have:** the post-merge half. Dropping the queue is not taken: our merge rate is far below the scale that motivated it (S11). Recorded as an owner question, F1. |
| S6 [Semantic constraints on approvals](https://www.anthropic.com/research/redesigning-source-control#what-we-learned-building-scion) | The review tool tells trivial edits from sensitive logic, so people review only the changes that matter. | Human reviewers were spread across changes of very different weight. **Stated** (same section) | The pr-merge gate's risk score sends LOW and size-only MEDIUM diffs to an unattended merge and holds the rest ([pr-pipeline README, risk score](../conventions/pr-pipeline/README.md#the-local-babysit-lane)); `/review:merge-risk` can only demote an unattended merge to a human ([SKILL.md](../../plugins/review/skills/merge-risk/SKILL.md)) | **already have:** the risk score and the demote-only rating. |
| S7 [Reviewing intent over lines](https://www.anthropic.com/research/redesigning-source-control#what-we-learned-building-scion) | People still sign off every change, but judge its intent rather than reading each line. | Line-by-line human reading cannot keep pace with agent-written volume. **Inference** | The pr-verify verdict binds a pull request to its one closing issue and judges the diff against that spec ([Verifier verdict](../conventions/pr-pipeline/README.md#verifier-verdict)) | **already have:** the verifier verdict judges alignment with intent. |
| S8 [Adversarial review drifts into over-engineering](https://www.anthropic.com/research/redesigning-source-control#what-we-learned-building-scion) | Engineers overrule review agents that add defensive complexity for hypothetical threats. | Adversarial review finds real bugs but can be narrow-sighted. **Stated** (same section) | Review findings that ask for unearned mechanism | **already have:** `/overengineering:justify` and the `plugins/source-control/reference/review-discipline.md` scope test. |
| S9 [Component health agents](https://www.anthropic.com/research/redesigning-source-control#what-we-learned-building-scion) | One agent per component watches its telemetry and logs for subtle faults beside the ordinary alerts. | Static alerts miss novel failure shapes. **Stated** (same section) | Lane health on GitHub Actions | **already have:** the hourly monitoring lane, no model ([The monitoring lane](../conventions/pr-pipeline/README.md#the-monitoring-lane)); an agent per component is not taken at our size. |
| S10 [Agents violating system constraints](https://www.anthropic.com/research/redesigning-source-control#what-we-learned-building-scion) | Engineers' main job became saying no when an agent works around a core rule of the system. | Agents follow a local pattern even when it breaks a system rule. **Stated** (same section) | Agents bypassing gates or reshaping denied commands | **already have:** the review lanes, the verifier verdict, and the AGENTS.md stop list. |
| S11 [Scope of the design](https://www.anthropic.com/research/redesigning-source-control#contributing-to-the-wider-ecosystem) | States who the design suits. | Not every repository has this problem. **Stated** (same section) | none | **already have:** recorded above as the limit on every S row. |
| C1 [Listener and selector](https://claude.com/resources/articles/agentic-coding-is-straining-ci-heres-how-we-scaled-test-impact-analysis-at-anthropic#the-test-impact-analysis-architecture) | Picks the tests each pull request runs from recorded past results and package relevance. | Running every test on every change makes the CI gate slow, costly and noisy, and agents need a precise test set to check their own work. **Stated** (same section) | Pull-request CI runs the suites `scripts/affected-tests.sh` maps from the changed paths, planned by `scripts/plan-test-lanes.sh`; `maintenance-audit-test-selection.yml` reports selection misses | **already have:** per-change selection by path, with a miss audit. History-based selection is not taken: no measured need. |
| C2 [Stateless workers over a shared journal](https://claude.com/resources/articles/agentic-coding-is-straining-ci-heres-how-we-scaled-test-impact-analysis-at-anthropic#the-bumpy-road-to-redesign) | Replaced a single-writer service with workers that append to an in-memory journal rolled up by a small consumer. | A single process holding per-test history could not shard and fell behind. **Stated** (same section) | none: we run no long-lived CI service | **reject:** no such service here. |
| C3 [Plan for many times today's CI load](https://claude.com/resources/articles/agentic-coding-is-straining-ci-heres-how-we-scaled-test-impact-analysis-at-anthropic#what-i-would-do-differently) | Advises sizing CI architecture for a large multiple of today's load and instrumenting so job counts in and out match. | Quick patches bought less time each round as agent output grew. **Stated** (same section) | Lane capacity limits | **already have:** `merge.max-in-flight` is computed from measured burst rate by `scripts/compute-max-in-flight.py`, and the monitoring lane tracks ceilings and throughput. A fixed multiplier is not taken: we size from measurement. |
| C4 [Smaller pull requests](https://claude.com/resources/articles/agentic-coding-is-straining-ci-heres-how-we-scaled-test-impact-analysis-at-anthropic#what-i-would-do-differently) | Notes that agents open smaller, more numerous pull requests, which raises CI job counts. | **Inference**: more, smaller changes shift load from review to CI. | Pull-request size | **already have:** the risk score's `lines-over` and `files-over` reasons. |
| R1 [Narrow review agents](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#test-ci) | Runs several reviewers per pull request, each scoped to one concern. | One broad reviewer shares one set of blind spots and spreads its effort thin. **Stated** (same section) | Review coverage | **already have:** the code-review and security-review lanes (`.github/workflows/pr-review-main.yml`, `pr-review-security-hosted.yml`) and `/review:fanout`. |
| R2 [Risk tiers for automation](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#governance) | Grades code areas by risk and automates review and approval only where the grade allows. | Agents must not merge sensitive code unchecked. **Stated** ([source](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#test-ci)) | Path-based holds exist but are off: `path-holds: false` (owner decision Q15, until open issues and pull requests reach zero) and `high-path-floor: false` (owner direction 2026-10-24) ([pr-pipeline README, risk switches](../conventions/pr-pipeline/README.md#the-pr-merge-lane)) | **already have:** the mechanism, switched off by the owner's phase decision. Turning it back on is the owner's call; not reopened here. |
| R3 [Logged approvals with reasons](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#governance) | Logs each automated approval together with the evidence and rationale it used. | Automated decisions must stay attributable and auditable. **Stated** (same section) | Auditing unattended merges | **already have:** the gate's decision reports, the `pr-merge-summary` artifact, the `<!-- babysit-merge-risk -->` reasons comment, and the merge-path rollup ([Merge paths](../conventions/pr-pipeline/README.md#merge-paths)). |
| R4 [Risk-weighted human sampling of approvals](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#governance) | People review a sample of automated approvals, weighted toward riskier ones. | An agent's approvals degrade unseen unless someone checks them. **Stated** (same section) | Unattended lane merges are judged afterwards only by red main, reverts and fix-PR escapes, not by a person reading a sample | **adapt:** a sampling read over merged lane pull requests would close the gap; it changes the merge lane's oversight, so it is handed on as F2. |
| R5 [Shadow mode for new reviewers](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#governance) | A new review agent only comments until it has earned trust. | An untested reviewer should not gate merges. **Stated** (same section) | Introducing a new gate | **already have:** `merge.report-only` starts the lane reporting only, and `pr-rate-merge-risk.yml` rates in report-only mode. |
| R6 [Closing the loop into instructions](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#code) | Each newly found bug class updates the agent instructions so it does not recur. | Written coding guidelines were hard to enforce. **Stated** (same section) | Repeated mistakes | **already have:** `/corrections:codify`. |
| R7 [Single-purpose agent identities](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#monitor) | Gives each agent the least permissions for one job and counts reach to other agents as part of its boundary. | An incident agent asked another agent to push a fix it could not push itself. **Stated** (same section) | Lane write access | **already have:** the dedicated lanes App identity and per-lane tokens ([Write identities](../conventions/pr-pipeline/README.md#write-identities)). |
| R8 [Egress-limited dev VMs, staging DAST, SIEM routing](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#deploy-cd) | Contains coding agents on allowlisted VMs, scans staging continuously, and sends every agent action to a SIEM. | Agents reading untrusted input, and subtle bugs that survive static review. **Stated** ([source](https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle#code)) | none here: no deployed service, no staging, no SIEM | **reject:** outside this repository's surface. |

## Figures the talk shows

Each figure below is **vendor-reported**: Anthropic's own measurement, not checked independently.
They appear only in this record, under the
[cost-claims rule's](../../.claude/rules/cost-claims.md) `docs/upstream/` exception; guidance
elsewhere links this section and copies none of them. Each was re-read from its primary source on
2026-11-12.

**Merged changes per day** (vendor-reported, post S, first paragraph and the first chart):

- About 2,500 per day in May 2026, stated as an average.
- More than 30,000 a day by September 2026, a figure the post gives with no averaging. The chart labels 30,401 as the count merged on one
  day, Sep 9; it is a single-day peak, not a daily average, and the chart's 7-day average ends
  well below it.
- The post does not define a code change. The chart counts pull requests and Antique change
  requests in one series, the second replacing the first from about July, so part of the growth
  may be a change of unit.

**SWE-bench Pro ladder** (vendor-reported, each figure from the system card named; the talk's
slide rounds them and notes that test settings vary by model):

| Model | Figure | Source and qualifier |
|---|---|---|
| Opus 4.5 | 52.0% and 51.6% | Two figures: without thinking and with 64k thinking, averaged over 5 trials. [Opus 4.5 system card](https://www.anthropic.com/claude-opus-4-5-system-card) |
| Opus 4.6 | 53.4% | From the [Opus 4.7 system card](https://www.anthropic.com/claude-opus-4-7-system-card), published after Opus 4.6; the [Opus 4.6 system card](https://www.anthropic.com/claude-opus-4-6-system-card) reports no SWE-bench Pro score |
| Opus 4.7 | 64.3% | [Opus 4.7 system card](https://www.anthropic.com/claude-opus-4-7-system-card) |
| Opus 4.8 | 69.2% | [Opus 4.8 system card](https://www.anthropic.com/claude-opus-4-8-system-card) |
| Fable 5 | 80 | Printed without a decimal. [Fable 5 and Mythos 5 system card](https://www.anthropic.com/claude-fable-5-mythos-5-system-card) |
| Opus 5 | 79.2% | [Opus 5 system card](https://www-cdn.anthropic.com/c5fbac3f0b1280a933ebd26d3cb8bb9f5bdeaf48/Claude%20Opus%205%20System%20Card.pdf) |
| Fable 5.1 | 81.2% | [Fable 5.1 and Mythos 5.1 system card](https://www.anthropic.com/claude-fable-5-1-mythos-5-1-system-card) |
| Opus 5.5 | 89.9% | [Opus 5.5 system card](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf) |
| Fable 5.2 | 93.0% | The slide's final point. In the [Fable 5.2 and Mythos 5.2 system card](https://www.anthropic.com/document/claude-fable-5-2-mythos-5-2-system-card) only (adaptive thinking at max effort, averaged over five trials); the [announcement](https://www.anthropic.com/claude-fable-and-mythos-5-2) text carries no SWE-bench Pro row |

- **Pointer**: when a figure above is cited, fetch its source live.
- **As of**: 2026-11-12
- **Recheck trigger**: a new system card publishes a SWE-bench Pro figure for a listed model, or
  post S changes its figures or chart.

## Owner decisions handed on

Each is listed in this record's pull request under `## Follow-ups` for the owner to decide. No
workflow or skill changed.

- **F1 Merge queue versus post-merge-only testing (S5).** Keep the merge queue plus the post-merge
  full run and red-main revert (recommended), widen merge groups or in-flight room further, or
  merge without the queue and rely on post-merge testing alone.
- **F2 Human sampling of unattended merges (R4).** Add no sampling (status quo), have a scheduled
  job pick a risk-weighted sample of merged lane pull requests for the owner to read, or fold a
  sample into an existing owner surface such as the morning brief (recommended).

## License notice

The three posts are Anthropic's published web pages; no license grants reuse of their text. This
record copies no upstream text and no image; it holds our descriptions, the vendor-reported figures
above as the cost-claims exception allows, and links.

- **Pointer**: the three posts listed under [Sources](#sources), each read for a license or reuse
  notice and found to carry none.
- **As of**: 2026-11-12
- **Recheck trigger**: a post adds a license or reuse notice.
