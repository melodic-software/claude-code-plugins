# Upstream source: "Building effective agent automations"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [Decisions](#decisions)
- [Handed to other sessions](#handed-to-other-sessions)
- [Correlating later posts](#correlating-later-posts)

This is the provenance record for acting on the claude.dev post about building scheduled agent
automations. It follows the record shape of [claude-dev-sonnet-5-5-blog.md](claude-dev-sonnet-5-5-blog.md)
and the [upstream-drift](../conventions/upstream-drift/README.md#required-parts) convention. Each
row is our decision in our own words; no row restates the post or a docs page.

## Status

This branch ships three docs changes: this record, the loop-lane convention's
[§8 Scheduled reader](../conventions/loop-lane/README.md#8-scheduled-reader) (convention 12.1.0),
and an amendment to [ADR 0062](../adr/0062-allow-api-keys-from-the-operator-s-own-linked-console-orgs.md)
that assigns each lane's role to one plan. Every other adopted item is its own open issue, named
in its row. The capacity work sits under #6958.

## Source and verification

- Correlate with `https://claude.dev/blog/building-effective-agent-automations/` (published
  2026-10-08, digested and dual-verified 2026-10-16). It is never the pointer where a docs section
  covers the topic.
- Figures the post reports, each vendor-reported and none carried elsewhere in this repository:
  3 to 5 (the multiple of a normal run's cost to start a run's spending cap at; vendor-reported:
  Guardrails, "Set the spending cap from real runs"); 500 cents (the example per-run budget;
  vendor-reported: the same section's budget example).
- Every rule the post states is a prompt rule for its reference agent. Where this repository meets
  one, it does so with a mechanism outside the prompt, named in the row.

## Row schema

**Topic** names the item with an ID other files cite; **Ours** is what this repository does or
decided, and where; **Pointer** is the docs section to fetch live when re-deriving the row, the
issue that carries the work, or a note that no docs page covers the topic, with the post as a
correlate. `none` marks an in-repo decision with no upstream section. Shared for every row:

- **As of**: 2026-10-16
- **Recheck trigger**: a re-read of the post finds a row no longer matching it; a pointed-to
  section is renamed or removed, or a docs page starts covering a topic whose pointer is the post
  (move the pointer there); or a cited issue closes, then replace its row's pointer with the
  shipped mechanism.

## Decisions

| Topic | Ours | Pointer |
|---|---|---|
| A1 Unreadable source | Adapted. morning-brief already renders each section as data, empty or `UNREADABLE` (`/harness-ops:morning-brief`, "Degraded sections"). ai-briefing gains the same per-source state, and a headless lane that loads MCP servers checks the init event's server status before it trusts an empty result: #7678 | When a lane must learn that a server failed to load, fetch [How Claude learns that a server failed](https://code.claude.com/docs/en/mcp#how-claude-learns-that-a-server-failed) and [Fail CI when a plugin or MCP server doesn't load](https://code.claude.com/docs/en/headless#fail-ci-when-a-plugin-or-mcp-server-doesnt-load) live; post, Sources (correlate) |
| A2 Confirm before recording | Adapted. Loop-lane's ordered writes (§2 "Escalation record write") and the telemetry read-back that reports `UNREPORTED` (§4 "Telemetry comment") are this repository's confirm-then-record pattern; no second state vocabulary. Overlapping runs get research first: which posting lanes run outside a `concurrency:` group, #7672. The PostToolUse hook idea is rejected, its feasibility unverified | #7672; no docs page covers confirm-then-record for lane posts as of 2026-10-16; post, Destination (correlate) |
| A3 Spend and turn caps on CI lanes | Adapted. A cap's value lives only in workflow YAML or a repo variable, never in a convention doc; the lane reads the result subtype and records `capped` in telemetry; the job timeout stays the outer backstop; a harness cap ends a run, so no pause-and-resume semantic; the first values come from measured runs. Run limits per task class that save progress and resume: #7677 | When setting a print-mode cap, fetch [CLI flags](https://code.claude.com/docs/en/cli-reference#cli-flags) live; #7677; post, Guardrails (correlate) |
| A4 Per-source bookmark | Adapted. With no `--since`, ai-briefing reads each source from its own bookmark, moved only after a full read, reusing morning-brief's bookmark mechanics; an explicit `--since` keeps the fixed window: #7678 | #7678; no docs page covers per-source bookmarks for a scheduled reader as of 2026-10-16; post, Sources (correlate) |
| A5 Untrusted text in the briefing skills | Adapted. morning-brief and ai-briefing frame ingested text per the [untrusted-content](../conventions/untrusted-content/README.md) convention, record their private-data, untrusted-text and outbound legs, and treat notes a lane re-reads as a poisoning route: #7678, #7679 | #7678, #7679; post, Guardrails (correlate) |
| A6 Dead-man's switch | Research more. An owner decision: which external absence-of-signal monitor, if any, and whether a push alert beats morning-brief's `STALE` pull view: #7673 | #7673; no docs page covers an external heartbeat for scheduled lanes as of 2026-10-16; post, Guardrails (correlate) |
| A7 Kill switch in the review and intake lanes | Deferred to #7234. [ADR 0049](../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md) decision 4 already counts an unreadable switch as off; the gap is lanes that do not read it | #7234 |
| A8 Untrusted framing in the intake workflows | Deferred to #7592 and #7394 | #7592, #7394 |
| A9 Where cloud-routine state lives | Research more. One probe routine writes state to a tracker comment and reads it back on its next run; until it reports, the tracker comment is the carrier, as loop-lane telemetry already is: #7674 | When choosing a routine's state carrier, fetch [Routines](https://code.claude.com/docs/en/routines) live; #7674; no docs page covers where a routine keeps state between runs as of 2026-10-16 |
| A10 Reader time zone | Adapted. A scheduled prompt this repository authors names the zone its date arithmetic uses where a date matters; morning-brief labels the zone on its stamps: #7679. Which zone is deferred to that issue's planning. A cloud routine's "today" is settled by A9's probe | When writing a scheduled prompt, fetch [Add a schedule trigger](https://code.claude.com/docs/en/routines#add-a-schedule-trigger), [How scheduled tasks run](https://code.claude.com/docs/en/scheduled-tasks#how-scheduled-tasks-run) and [Run on a schedule](https://code.claude.com/docs/en/github-actions#run-on-a-schedule) live |
| A11 This record | Adopted: this file | none |
| A12 Scheduled-reader section | Adapted. One section of pointers, not a new checklist: loop-lane [§8 Scheduled reader](../conventions/loop-lane/README.md#8-scheduled-reader) maps each of the post's six rules to the mechanism that meets it or the issue that adds it. Its readers are authors of new scheduled lanes | none |
| A13 Read-only preferences and sandbox completeness | Met for CI lanes: the headless-config floor (loop-lane §4) and base-SHA config in `.github/workflows/pr-run-activity-read.yml`. Local lanes: research more, listing the lanes that read an editable preferences file, and add the sandbox-conditions note only where one exists: #7680 | When judging whether a deny rule protects a file, fetch [Configure sandboxing](https://code.claude.com/docs/en/sandboxing#configure-sandboxing) live; #7680 |
| A14 Re-check live state before posting | Already met: the feedback lane re-reads each thread and the head ref right before each post (`docs/conventions/pr-pipeline/pr-run-activity.md`, "prepare: review-threads"), and re-reads holds before promote (#7548, merged). No new artifact | none |
| A15 Per-item ledger | Deferred: whether morning-brief's readers need what changed since the last brief. If they do, it folds into #7578 or a new issue | #7578; no docs page covers a per-item report ledger as of 2026-10-16 |
| A16 Open egress for CI lanes | Deferred: a security-class owner question whose trade-off ADR 0049 records. Revisit only with evidence that hosted runners offer default-deny egress | [ADR 0049](../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md) |
| A17 Approval defaults per surface | Rejected as a new artifact: `AGENTS.md` already fixes the permission mode per lane surface (`auto` for local lanes, `dontAsk` for intake, `acceptEdits` for review) | When a lane's approval behavior is in question, fetch [Available modes](https://code.claude.com/docs/en/permission-modes#available-modes) and [Turn off permission prompts in unattended runs](https://code.claude.com/docs/en/headless#turn-off-permission-prompts-in-unattended-runs) live |
| A18 Managed Agents as an execution target | A track of its own: map the Managed Agents docs corpus, then pick a first credit-funded workload, #7675. Allocation stays on #6970 | When evaluating it, fetch [Managed Agents overview](https://platform.claude.com/docs/en/managed-agents/overview) and [Scheduled deployments](https://platform.claude.com/docs/en/managed-agents/scheduled-deployments) live; #7675 |
| A19 Onboarding path and reference implementation | Rejected: a version-floor skill rule, since `.claude/rules/skill-bodies-state-current-rules.md` already allows the pointer and forbids a restated version. Running the onboarding is the operator's call; the reference implementation's agent definition is read only inside #7675 | #7675 |
| A20 Brevity and links from the source | Rejected: ai-briefing already requires a working source URL per item and forbids invented details (`plugins/ai-briefing/skills/generate/SKILL.md`) | none |
| A21 Digest tagging rulings | Deferred inside the digest slice; no repository decision depends on them | none |

## Handed to other sessions

- **poteto** (morning-brief, ai-briefing, epic #7555): the A1, A4 and A5 items as #7678, now a
  sub-issue of #7555, and the A5 and A10 items as #7679, now a sub-issue of #7578, the work-items
  thread that owns morning-brief.
- **Automation Lanes** (CI lanes, caps, rotation): #7672, #7675, #7676 (a private, aggregatable
  transcript store), #7677, and the ADR 0062 amendment. It updates the issues it owns from that
  handoff: #6958, #6962, #6967, #6970, #6972, #6973 and #6974.
- **claude-code-account-rotation**: the usage panel, operator alerts and rebalance button,
  melodic-software/claude-code-account-rotation#255.

## Correlating later posts

A later claude.dev post on scheduled agent automations is correlated here: add it as a correlate
note beside the row it touches, and move a row's pointer only to a docs section, never to a post.
