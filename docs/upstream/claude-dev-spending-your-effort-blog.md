# Upstream source: "Using Claude Code: Spending your effort"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [Decisions](#decisions)
- [Handed to other sessions](#handed-to-other-sessions)
- [Correlating later posts](#correlating-later-posts)

This is the provenance record for acting on the claude.dev post about choosing an effort level in
Claude Code. It follows the record shape of [claude-dev-sonnet-5-5-blog.md](claude-dev-sonnet-5-5-blog.md)
and the [upstream-drift](../conventions/upstream-drift/README.md#required-parts) convention. Each
row is our decision in our own words; no row restates the post or a docs page. This record lists
no figure from the post.

## Status

The decisions were made in one interview, decisions only, with every edit, pull request, comment
and corpus move held for the user's go-ahead. The interview settled concrete levels and files;
planning chose the edit order and wording. Decisions on files another session had claimed went to
that session by message and landed in its pull request; this branch edited only unclaimed files.
The work landed in two pull requests: [#5920](https://github.com/melodic-software/claude-code-plugins/pull/5920)
(merged 2026-10-03) and the pull request carrying this record, which adds it as its last commit.

Dropped or held, each needing the user's go-ahead before it runs:

- Choosing the implementer's model per phase inside implement-dispatch was dropped: phases the
  plan marks for Sonnet go to the task-cost branch's `implementation:scoped-implementer` instead.
- A delegation posture is deferred until an official prompting guide states one.
- No docs cache is built here; a repo-wide issue for it is drafted and shown before filing.
- Dating the agent pin count in [claudedevs-cost-performance.md](claudedevs-cost-performance.md)
  was dropped: [#5767](https://github.com/melodic-software/claude-code-plugins/pull/5767) replaced
  the count with a pointer.
- Held for the user: an eval of the object-writer agent across effort levels (it settles
  [E4](#decisions)); a correction round on the digest slice; graduating the slice to the knowledge
  corpus in its own draft pull request; comments on
  [#4253](https://github.com/melodic-software/claude-code-plugins/issues/4253) and
  [#4346](https://github.com/melodic-software/claude-code-plugins/issues/4346). The replay sweep
  that re-decides the implementer's level and the Sonnet-bound review pins belongs to
  [#5682](https://github.com/melodic-software/claude-code-plugins/issues/5682); its scope was
  approved and posted there.

## Source and verification

- Correlate with `https://claude.dev/blog/spending-your-effort` (published 2026-09-25, digested
  and dual-verified 2026-09-29). It is never the pointer where a docs section covers the topic.
  Recheck trigger: the post is revised, or a later claude.dev post on effort supersedes it.
- Pointer for effort levels in Claude Code: [Model configuration](https://code.claude.com/docs/en/model-config),
  sections named per row, read 2026-10-02.
- Pointers for hook input fields, prompt caching, skill substitutions and telemetry: the Claude
  Code docs pages named per row, read 2026-10-02.
- Where no docs page covers a topic, the row says so, links the post section as the correlate
  note, and its recheck trigger includes a docs page starting to cover it.

## Row schema

**Topic** names the item with an ID other files cite; **Ours** is what this repository now does
and where; **Pointer** is the docs section a reader checks live, followed by the post section as
correlate note. Shared for every row:

- **As of**: 2026-10-02
- **Recheck trigger**: the pointed-to section is renamed or removed, stops covering its topic, or
  its effort table's rows or columns change; for a row whose topic no docs page covers, a docs page
  starting to cover it.

## Decisions

| Topic | Ours | Pointer |
|---|---|---|
| E1 Lane effort | Every lane launches with an explicit level chosen per lane: verdict lanes at the level the table gives work where verification matters, the coordinating merge lane at its model's default passed explicitly, code and verify work never below medium. The launcher refuses a lane whose config names no `effort` and warns when the effort environment variable can override lanes and agent pins. [loop-lane-prompts.md](../../prompts/loops/loop-lane-prompts.md) (Models), [config.md](../../plugins/harness-ops/skills/lanes/context/config.md), [lane-launcher.sh](../../plugins/harness-ops/skills/lanes/scripts/lane-launcher.sh). Supersedes the lanes half of [B1](claude-dev-sonnet-5-5-blog.md#decisions) | [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); correlate [When to use different effort levels in Claude Code](https://claude.dev/blog/spending-your-effort#when-to-use-different-effort-levels-in-claude-code) |
| E2 Lane records the level that ran | The work-loop and babysit-loop state blocks record the effort each cycle ran at, or `unset`, since a passed level can be clamped or overridden. [work-loop SKILL.md](../../plugins/work-items/skills/work-loop/SKILL.md), [babysit-loop SKILL.md](../../plugins/source-control/skills/babysit-loop/SKILL.md) | [Common input fields](https://code.claude.com/docs/en/hooks#common-input-fields); correlate [the post](https://claude.dev/blog/spending-your-effort) |
| E3 Implementation agent pins | The phase verifier stays at high and the implementer at medium, as [#5885](https://github.com/melodic-software/claude-code-plugins/pull/5885) set them; that pull request superseded this interview's answer to keep the implementer at high. Both agents' upward-only binding now covers a shipped Workflow script's `effort` and `model`. [phase-verifier.md](../../plugins/implementation/agents/phase-verifier.md), [implementer.md](../../plugins/implementation/agents/implementer.md) | [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); correlate [Higher effort levels help when there are many edge cases](https://claude.dev/blog/spending-your-effort#higher-effort-levels-help-when-there-are-many-edge-cases) |
| E4 Object-writer pin | Pinned at medium, provisional until an eval compares levels. [object-writer.md](../../plugins/songwriting/agents/object-writer.md) | [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); correlate [Building with effort](https://claude.dev/blog/spending-your-effort#building-with-effort) |
| E5 Review and other agent pins | Confirmed unchanged: the security reviewer and architecture guardian stay at high with no max pin. [security-reviewer.md](../../plugins/review/agents/security-reviewer.md), [architecture-guardian.md](../../plugins/review/agents/architecture-guardian.md) | [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); correlate [Problem areas where effort helps](https://claude.dev/blog/spending-your-effort#problem-areas-where-effort-helps) |
| E6 Pin drift check | A tested script hashes the docs' effort sections against a committed baseline and flags, never edits, any pin, lane level or Workflow literal that rests on a changed table or default. It runs from the audit's `effort-pins` scope and checklist row and on each Claude Code release through the changelog skill. [check-effort-pins.sh](../../plugins/harness-config/skills/audit/scripts/check-effort-pins.sh), [audit-checklist.md](../../plugins/harness-config/skills/audit/reference/audit-checklist.md), [changelog SKILL.md](../../plugins/harness-ops/skills/changelog/SKILL.md) | [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level), [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); correlate [the post](https://claude.dev/blog/spending-your-effort) |
| E7 Per-phase effort advice | Skills advise a level per phase by having the model read the live table and name the row it matched; no level is written into skill text, code and verify phases are never advised below medium, and an unreadable page means no advice. The interview's handoff advises implement and verify levels separately; continue-in-background passes the matched level for resumed verify or unattended work. [steps.md](../../plugins/session-flow/skills/workflow/context/steps.md), [continue-in-background SKILL.md](../../plugins/session-flow/skills/continue-in-background/SKILL.md), [session-config.md](../../plugins/planning/skills/interview/context/session-config.md) | [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level), [Set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level); correlate [Takeaways](https://claude.dev/blog/spending-your-effort#takeaways) |
| E8 Cheap tier excludes code, verify and edge-case work | Work that changes code, verifies a change, or is likely to hit edge cases never takes the lower effort that high-volume mechanical work gets. [orchestrate SKILL.md](../../plugins/session-flow/skills/orchestrate/SKILL.md) (imperative 7), [plugin-philosophy.md](../../docs/plugin-philosophy.md#effort-tiers) | [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); correlate [Higher effort levels help when there are many edge cases](https://claude.dev/blog/spending-your-effort#higher-effort-levels-help-when-there-are-many-edge-cases) |
| E9 Workflow effort in shipped scripts | Fanout's generic slices run at an explicit level, named agents keep their pins, and the report names each leaf's level. No docs page covers per-call Workflow effort as of 2026-10-02; the pointer is our probe. [run-everything-mode.md](../../plugins/review/skills/fanout/context/run-everything-mode.md) | Probe: the "Our Workflow probe" paragraph of [Effort tiers](../plugin-philosophy.md#effort-tiers); correlate [the post](https://claude.dev/blog/spending-your-effort) |
| E10 map-corpus effort gotcha | The gotcha is a pointer to the same probe record instead of its own claim. [map-corpus SKILL.md](../../plugins/knowledge/skills/map-corpus/SKILL.md) | Probe: [Effort tiers](../plugin-philosophy.md#effort-tiers); correlate [the post](https://claude.dev/blog/spending-your-effort) |
| E11 Event-log effort and fields | Rows record the effort level (`n/a` on events that never carry one, `unset` when missing), the documented non-content input fields, and absolute path fields as-is. Content strings are opt-in, off by default; a string cut by the read cap is recorded as a prefix with a `_truncated` marker, a row whose payload reached the cap carries `content_truncated`, and long rows append under a lock. [session-event-log.sh](../../plugins/harness-ops/hooks/session-event-log.sh), [session-log-lib.sh](../../plugins/harness-ops/hooks/session-log-lib.sh), [data-sources.md](../../plugins/harness-ops/skills/observability/context/data-sources.md), [privacy.md](../../plugins/harness-ops/skills/observability/context/privacy.md) | [Common input fields](https://code.claude.com/docs/en/hooks#common-input-fields); correlate [the post](https://claude.dev/blog/spending-your-effort) |
| E12 unhobble records effort | The unhobble manifest and each stumble row carry the session's effort, or `unset`. [unhobble SKILL.md](../../plugins/harness-config/skills/unhobble/SKILL.md) | [Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions); correlate [the post](https://claude.dev/blog/spending-your-effort) |
| E13 OTEL store schema | The store promotes every documented telemetry attribute and keeps the raw attributes; token and cache queries group by model and effort with `unset` for none. Cold storage scrubs user prompts by default as before, and a new switch scrubs the other content columns only when set to `0`. [cc-otel.sql](../../plugins/harness-ops/skills/observability/otel/cc-otel.sql), [session-compare.sql](../../plugins/harness-ops/skills/observability/otel/session-compare.sql), [privacy.md](../../plugins/harness-ops/skills/observability/context/privacy.md) | [Available metrics and events](https://code.claude.com/docs/en/monitoring-usage#available-metrics-and-events); correlate [the post](https://claude.dev/blog/spending-your-effort) |
| E14 HTML quote gate | The digest pipeline's check for quotes taken from a page's HTML is a standing script with a synthetic negative-control suite, listed beside the other standing gates. Our tooling; no docs page covers it. [check-html-rows.py](../../plugins/knowledge/skills/docpage-digest/scripts/check-html-rows.py), [dual-verification.md](../../plugins/knowledge/skills/docpage-digest/context/dual-verification.md) | Probe: [test_check_html_rows.py](../../plugins/knowledge/skills/docpage-digest/scripts/test_check_html_rows.py); correlate [Effort curves](https://claude.dev/blog/spending-your-effort#effort-curves) |
| E15 Prompt-caching effort note | The playbook's effort section is scoped to API requests and sends Claude Code sessions to Claude Code's own cache page. [prompt-caching.md](../../plugins/playbooks/reference/prompt-caching.md) | [Changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level); correlate [the post](https://claude.dev/blog/spending-your-effort) |

## Handed to other sessions

Decisions on files other sessions owned were sent to them; their pull requests and records own the
landing:

- The Sonnet 5.5 prompting session, [#5767](https://github.com/melodic-software/claude-code-plugins/pull/5767)
  (merged): the doctrine's Effort tiers changes in [plugin-philosophy.md](../plugin-philosophy.md#effort-tiers)
  (the Workflow probe record, per-task effort through Workflow with the agent pin as the Agent-tool
  fallback, every agent pinned, advise a session level but never set it, scoped skill and agent
  pins as the stated exception, the shipped-script rule, and the prompt-caching pointer);
  `/verification:confirm` pinned at high and reporting its level; the docpage-digest gotcha
  pointer and the Anthropic docs profile's blog rules; the Opus 5.5 and Fable 5.1 chapter edits.
  The boris default row became a pointer in [#5759](https://github.com/melodic-software/claude-code-plugins/pull/5759).
  That session exited before this pull request, so the audit checklist's drift-check row, the
  edge-case exclusion in the bulk-mechanical rule and the prompt-caching scope sentence landed
  here ([E6](#decisions), [E8](#decisions), [E15](#decisions)).
- The task-cost session, [#5827](https://github.com/melodic-software/claude-code-plugins/pull/5827)
  (merged): `implementation:scoped-implementer` for Sonnet phases; its record is
  [opus-5-5-task-cost.md](opus-5-5-task-cost.md). It handed the implementation agent pin notes
  back to this branch ([E3](#decisions)).

## Correlating later posts

A later claude.dev post on effort is correlated here: add it as a correlate note beside the row it
touches, and move a row's pointer only to a docs section, never to a post.
