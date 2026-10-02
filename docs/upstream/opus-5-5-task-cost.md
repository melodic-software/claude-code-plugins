# Upstream source: "What a task costs on Opus 5.5"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [The cost of a task, and the cost of a retry](#the-cost-of-a-task-and-the-cost-of-a-retry)
- [What does a task cost?](#what-does-a-task-cost)
- [What changed in Opus 5.5](#what-changed-in-opus-55)
- [The same tasks side-by-side](#the-same-tasks-side-by-side)
- [Tips for maximizing the value of your session](#tips-for-maximizing-the-value-of-your-session)
- [Measure it yourself](#measure-it-yourself)
- [Keep in mind](#keep-in-mind)
- [Conflicts](#conflicts)
- [Decisions and follow-ups](#decisions-and-follow-ups)

This is the provenance record for this repository's response to the claude.dev post "What a task
costs on Opus 5.5". It follows the record shape of [opus-5-5-usage-guide.md](opus-5-5-usage-guide.md)
and [claude-dev-sonnet-5-5-blog.md](claude-dev-sonnet-5-5-blog.md), and the
[upstream-drift](../conventions/upstream-drift/README.md#required-parts) convention. Each row maps
one post item to the official docs section this repository trusts for it, and says what the
repository does. The post's figures appear only in this file, each labelled vendor-reported. Every
place where the post and the docs, or two docs pages, disagree is in [Conflicts](#conflicts).

## Status

Draft on branch `feat/opus-5-5-task-cost-digest`, tracked by parent issue
[#5763](https://github.com/melodic-software/claude-code-plugins/issues/5763). The branch lands as
one draft pull request that closes #5763 (Q45).

A row marked ADOPTED names the file a later phase of this branch edits. It is planned work, not
landed work, until that pull request merges. Rows that other sessions own name their doer and pull
request in [Decisions and follow-ups](#decisions-and-follow-ups).

## Source and verification

- Correlate: `https://claude.dev/blog/what-a-task-costs-on-opus-5-5/`, by Addy Osmani, published
  2026-09-25, fetched 2026-09-29 for the digest, read for this record 2026-10-01. Recheck trigger:
  the post is revised, or a later claude.dev post on Opus cost supersedes it. The post is never the
  pointer where a docs section covers the topic (Q38).
- Pointers: the Claude Code docs at `https://code.claude.com/docs/en/` and the Claude platform docs
  at `https://platform.claude.com/docs/en/`, sections named per row. Each page was read as raw
  markdown on 2026-10-01, and each anchor was confirmed against the heading ids on the rendered page
  the same day.
- A citation of the post carries only its canonical link, publish date, date last checked and
  recheck trigger (Q13). A docs pointer carries the Checked date and Recheck trigger columns below
  (Q44).
- No local measurement was run. Rows act on the docs as written, and a disagreement between two
  official sources is logged with a recheck trigger (Q4).
- Evidence standing: Anthropic's docs, changelog and blogs count as one publisher for facts about
  Anthropic's own product, so every claim here is vendor-documented MEDIUM; none is independently
  settled (research gap G5).
- Rules applied (Q38): links only, with no restated values; main docs over blog posts, with the
  post as a correlate note; never file issues on Anthropic repositories; default to what Anthropic's
  docs prescribe, and state the reason for any deviation (two are stated in
  [Decisions and follow-ups](#decisions-and-follow-ups)).

## Row schema

Each row is a four-part record: the claim or decision (**Post item** and **Ours**), the basis
(**Official docs section**), the as-of date (**Checked**) and the **Recheck trigger**. A figure
quoted from the post is marked "vendor-reported" in the Post item column. Q numbers cite the
interview ledger, `.work/opus-5-5-task-cost-interview/interview-checklist.md` (Q1 to Q49).

Verdicts:

- **ADOPTED**: this branch changes the file named in Ours, in the phase named there.
- **POINTER**: this record points at the docs section and the repository restates nothing.
- **COVERED**: an existing repository surface already does it; Ours names it.
- **NOT ADOPTED**: deliberately not carried into repository guidance; Ours gives the reason.
- **VENDOR CLAIM**: stated only in the post; no docs section covers it as of the Checked date.
- **GAP**: a question no docs section answers as of the Checked date.
- **OWNER**: the item sits in a file another session owns; see Decisions and follow-ups.

Default recheck trigger, written as "section moves": the pointed-to section is renamed, removed,
or stops covering the item.

## The cost of a task, and the cost of a retry

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| A task costs turns times the context each turn resends, so the same per-token price can cost different amounts per task | [Manage costs: Why usage climbs in a long session](https://code.claude.com/docs/en/costs#why-usage-climbs-in-a-long-session) | No repository-authored cost explanation (Q36, which replaced Q27). Phase 2 links this section from `plugins/playbooks/reference/prompt-caching.md` (session-side section) and `plugins/planning/skills/draft-goal-condition/SKILL.md` (Gotchas) | ADOPTED (Q36) | 2026-10-01 | Section moves |
| "A retry costs more than those savings" (vendor-reported) | [Manage costs: Work efficiently on complex tasks](https://code.claude.com/docs/en/costs#work-efficiently-on-complex-tasks) | Not restated and not made a rule (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | Section moves, or a docs page states the comparison |
| The figures are illustrations; check the docs and your own math | [Manage costs: Track your costs](https://code.claude.com/docs/en/costs#track-your-costs) | Phase 2 adds `.claude/rules/cost-claims.md`, a path-scoped rule: cost claims point at the costs doc and the pricing page and state no prices or per-task figures; `docs/upstream/` records may list vendor figures labelled vendor-reported. No audit check (Q28) | ADOPTED (Q28) | 2026-10-01 | Section moves |

## What does a task cost?

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Four drivers: turns, cache reads, output tokens with thinking billed as output, and the model's prices | [Pricing: Model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing); [Manage costs: Adjust extended thinking](https://code.claude.com/docs/en/costs#adjust-extended-thinking) | Pointers only; the cost-claims rule points at the pricing page for rates (Q28, Q36) | POINTER (Q36) | 2026-10-01 | Either section moves |
| Example prices and token counts (vendor-reported): Opus 5.5 at $4 input, $20 output and $0.20 cache read per million tokens; a 40-turn task of about 2.8M input tokens costing about $1.62 at a 90% cache hit rate, about $1.02 in 25 turns, $11.20 with no cache and about $0.99 at 96%; 60K output tokens costing $1.20; "No other setting moves input cost this much" | [Pricing: Model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing) | Kept out of repository guidance (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | The pricing table changes |
| The examples leave out cache writes | [Pricing: Prompt caching](https://platform.claude.com/docs/en/about-claude/pricing#prompt-caching) | Phase 4's `claude-ops:observability` compare reports cache writes (`cacheCreation`) as their own token type and compares token counts, not dollars (Q7, Q22) | ADOPTED (Q22) | 2026-10-01 | Section moves |
| Give the model a way to check its work, to cut turns | [Best practices: Give Claude a way to verify its work](https://code.claude.com/docs/en/best-practices#give-claude-a-way-to-verify-its-work); [Manage costs: Work efficiently on complex tasks](https://code.claude.com/docs/en/costs#work-efficiently-on-complex-tasks) | Pointer in this record; no new posture row (Q30) | POINTER (Q30) | 2026-10-01 | Either section moves |
| A model that gathers context in one pass and batches its tool calls pays the resend fewer times | Checked: [Manage costs: Reduce token usage](https://code.claude.com/docs/en/costs#reduce-token-usage); no docs section states it | Nothing built (Q47, batching claim) | VENDOR CLAIM (Q47) | 2026-10-01 | A docs page starts covering it |
| Effort mostly changes how much the model thinks; thinking is billed even when only a summary shows | [Model configuration: Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking) | The docs' wording, not the post's (Q30); see the thinking row in Conflicts | POINTER (Q30) | 2026-10-01 | Section moves |

## What changed in Opus 5.5

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Every price line is lower than on Opus 5 (vendor-reported): input and output 20% cheaper, cache reads 60% cheaper, the cache-read rate moving from a tenth to a twentieth of the input price; Fig A's Opus 5 prices of $5, $25 and $0.50 per million tokens | [Pricing: Model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing); [Models overview](https://platform.claude.com/docs/en/models/overview) | Kept out of repository guidance (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | The pricing table changes |
| Plan limits go about 25% further than on Opus 5 (vendor-reported); five-hour limits raised; a limit reset under Settings > Usage | Checked: [Manage costs: Plan usage breakdown](https://code.claude.com/docs/en/costs#plan-usage-breakdown); no docs section states the pass-through or the reset | Nothing built; the repository points at `/usage` plan bars (Q47, plan claims) | VENDOR CLAIM (Q47) | 2026-10-01 | A docs page states it |
| "Opus 5.5 costs 40% less to run than Opus 5" (vendor-reported estimate for typical workloads at default settings) | [Model configuration: Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level) | Kept out of repository guidance (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | Section moves |
| On a well-scoped task both models finish in about the same number of turns; the gap is widest on open-ended tasks | [Model configuration: Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level) | Nothing built; the Phase 4 compare is the measuring tool (Q22) | VENDOR CLAIM (Q22) | 2026-10-01 | A docs page states it |
| Long runs end with a report of what changed, what was found and what is needed | [Prompting Claude Opus 5.5: Unattended agentic runs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#unattended-agentic-runs) | A closing report is not proof of done. Covered by the root `AGENTS.md` task-list rule, `/goal` conditions (`/planning:draft-goal-condition`) and loop exit checks. The guide's cap on automatic continuations is not stated anywhere in this repository (Q26) | COVERED (Q26) | 2026-10-01 | Section moves, or a repository loop gains automatic continuation |

## The same tasks side-by-side

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Fig B and Fig C (vendor-reported): one session costing $3.50 at Opus 5 list prices and $2.40 on Opus 5.5, 31% less, $242 a month less at 10 tasks a day over 22 working days | [Pricing: Model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing) | Kept out of repository guidance (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | The pricing table changes |
| The receipt shows the lines `/usage` reports for a session | [Manage costs: Using the `/usage` command](https://code.claude.com/docs/en/costs#using-the-%2Fusage-command) | No repository `/usage` reference; the docs section is the reference (Q47). The post's line count is in Conflicts | NOT ADOPTED (Q47) | 2026-10-01 | Section moves |
| Fill the calculator from `/usage`, run the same task on both models, and set the token-change slider from that comparison | [Monitoring: Token counter](https://code.claude.com/docs/en/monitoring-usage#token-counter) | Phase 4: the `compare` action in `plugins/claude-ops/skills/observability/` (Q22) | ADOPTED (Q22) | 2026-10-01 | Section moves |

## Tips for maximizing the value of your session

### Raise effort before you change models

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Effort ladder: medium for well-scoped daily work, high when medium stalls, low for mechanical work | [Model configuration: Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); [Effort: Recommended effort levels for Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/effort#recommended-effort-levels-for-claude-opus-5-5) | Pointer in this record; `plugins/playbooks/reference/model-adaptation/opus-5-5.md` unchanged (Q30, Q37) | POINTER (Q30) | 2026-10-01 | Either section moves, or the next Opus release |
| The effort picker's labels, quoted from the post's HTML (vendor-reported): "low mechanical", "medium everyday", "high if it stalls", "xhigh hard problems", "max one session" | [Model configuration: Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level) | Graduates only as this cited quote (Q34); repository text that names an effort for hard problems follows the docs table (Q9). See Conflicts | POINTER (Q9, Q34) | 2026-10-01 | Section moves |
| Opus 5.5 defaults to medium; do not carry over a level chosen for Opus 5 | [Model configuration: Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level) | The two repository lines that stated "default high" now point at this section (Q19) | OWNER (Q19, landed) | 2026-10-01 | Section moves |
| Effort pricing illustration (vendor-reported): 20K thinking tokens cost $0.40 on Opus 5.5, about the same as a retry loop of ten turns at 100K cached context | [Pricing: Model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing) | Kept out of repository guidance (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | The pricing table changes |
| When medium fixes one layer, a check that runs through the second layer catches it before more effort does | [Best practices: Give Claude a way to verify its work](https://code.claude.com/docs/en/best-practices#give-claude-a-way-to-verify-its-work) | Pointer in this record (Q30) | POINTER (Q30) | 2026-10-01 | Section moves |
| Change effort mid-session with `/effort`; raise it for one hard step and lower it again | [Model configuration: Set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level); [Model configuration: Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level) | Pointer in this record. The docs' session-only confirm (`s` in the slider or picker) is the route for a one-step change, because a typed level is saved as the default (Q30) | POINTER (Q30) | 2026-10-01 | Either section moves |
| On Opus 5.5 an effort change keeps the cache with an API key or a subscription, but not on Bedrock, Google Cloud's Agent Platform or a gateway | [How Claude Code uses prompt caching: Changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level) | Repository text follows the docs' list (Q15). The `criteria.md` I17-b update is held by its owner (Q32). See Conflicts | OWNER (Q15, Q32) | 2026-10-01 | Section moves |

### Choose the right model for your work

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Three models: a small one for lookups, Opus 5.5 for supervised work, a bigger one for the hardest tasks | [Manage costs: Choose the right model](https://code.claude.com/docs/en/costs#choose-the-right-model) | Phase 5 adds a per-phase `Model` column (`sonnet`, `opus`, `frontier`) to `plugins/planning/skills/plan/context/plan-template.md` (Q20, Q41) | ADOPTED (Q20) | 2026-10-01 | Section moves |
| Move up to Fable 5.1 when Opus 5.5 at xhigh hits the same problem twice, and switch back once it is solved | [Choosing the right model: Option 2](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model#option-2-start-capability-first) | Pointer in this record; the "twice" rule is the post's own (Q30). See Conflicts | POINTER (Q30) | 2026-10-01 | Section moves, or the next Fable release |
| Switching models pays a cache write on the whole conversation; run `/compact` first or start fresh with a written plan; `/model` saves the choice as the default | [How Claude Code uses prompt caching: Switching models](https://code.claude.com/docs/en/prompt-caching#switching-models); [Model configuration: Setting your model](https://code.claude.com/docs/en/model-config#setting-your-model) | No model-switch guard hook built; the docs' confirm prompt and `PreModelSwitch` hook already cover it (Q47, cache hooks) | NOT ADOPTED (Q47) | 2026-10-01 | Either section moves |
| Move down to Sonnet or Haiku for lookups, not for writing code; keep code edits on Opus 5.5 | [Manage costs: Choose the right model](https://code.claude.com/docs/en/costs#choose-the-right-model) | Phase 5: `plugins/implementation/agents/scoped-implementer.md` (`model: sonnet`, `effort: medium`) takes plan rows marked `sonnet`; `plugins/implementation/skills/implement-dispatch/SKILL.md` routes them. The post's code-edit advice is in Conflicts (Q20, Q41) | ADOPTED (Q20) | 2026-10-01 | Section moves |
| Subagent model: set `model:` in the definition, or `CLAUDE_CODE_SUBAGENT_MODEL` for all of them | [Create custom subagents: Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model); [Run every subagent on one model](https://code.claude.com/docs/en/sub-agents#run-every-subagent-on-one-model) | `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` stays declined, and repository text follows the docs' order (Q5). `docs/upstream/claude-code.md` Declined row updated in Phase 1 (Q39). See Conflicts | ADOPTED (Q5, Q39) | 2026-10-01 | Either section moves |
| How the built-in Plan subagent picks its model (not in the post; asked at Q14) | [Create custom subagents: Built-in subagents](https://code.claude.com/docs/en/sub-agents#built-in-subagents) | Plan inherits the main conversation's model unless `CLAUDE_CODE_SUBAGENT_MODEL` is set and forced onto every subagent; Explore is capped at Opus on the Claude API. No `Plan.md` override is added; the user's per-spawn routing rule stays (Q14) | NOT ADOPTED (Q14) | 2026-10-01 | Section moves |
| A subagent with no `model:` runs on the main model | [Create custom subagents: Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model) | `scripts/validate-plugin-contracts.mjs:1074-1116` fails any shipped agent without `model:` ([#4568](https://github.com/melodic-software/claude-code-plugins/pull/4568)); no new routing rule (Q24) | COVERED (Q24) | 2026-10-01 | Section moves |
| Agent teams multiply cost (vendor-reported: about seven times the tokens of a standard session in plan mode); `opusplan` plans on Opus and executes on Sonnet | [Manage costs: Manage agent team costs](https://code.claude.com/docs/en/costs#manage-agent-team-costs); [Model configuration: `opusplan` model setting](https://code.claude.com/docs/en/model-config#opusplan-model-setting) | Phase 5 links both sections from the plan template's routing guidance, restating no figure (Q25) | ADOPTED (Q25) | 2026-10-01 | Either section moves |
| A small model that misreads a search result sends the main model after the wrong file | [Manage costs: Delegate verbose operations to subagents](https://code.claude.com/docs/en/costs#delegate-verbose-operations-to-subagents) | Nothing built; the Phase 5 `sonnet` route requires a closed scope and binary acceptance criteria (Q20) | VENDOR CLAIM (Q20) | 2026-10-01 | A docs page states it |

### Check your prompts when you migrate

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Run `/claude-api prompt-audit` to check your Claude Code setup | [How Claude remembers your project: Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files); [Skills: Work on Claude API projects](https://code.claude.com/docs/en/skills#work-on-claude-api-projects) | Already on main: the `/doctor prompt-audit` Boundary in `plugins/claude-config/skills/audit-instructions/SKILL.md:115-129` and `reference/native-doctor.md` ([#5387](https://github.com/melodic-software/claude-code-plugins/pull/5387)). Phase 2 names it in the audit-instructions Routing paragraph, `plugins/claude-config/skills/audit-pass/SKILL.md` and `reference/doctor-handoff.md`, and `audit-instructions/reference/bundled-claude-api.md` (Q8); and in the Follow-ups of `docs/specs/prompt-audit-skills-2026-09.md`, with ADR-0028 unchanged (Q48) | ADOPTED (Q8, Q48) | 2026-10-01 | Either section moves, or a release note changes either command's scope |
| Overlap between `/claude-config:audit-instructions` and `/doctor prompt-audit` | [How Claude remembers your project: Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files) | audit-instructions keeps its report-only catalog beside `/doctor prompt-audit`, each owning its rows (Q17). The 12 overlapping rows stay (Q42); see Decisions and follow-ups | COVERED (Q17, Q42) | 2026-10-01 | Section moves, or `/doctor prompt-audit` becomes model-invocable |
| A migration benchmark (vendor-reported): 44 tickets, the move to Opus 5.5 at low effort cutting cost by about 18%, prompt-audit cutting a further 9%, about 25% below the Opus 4.8 start; four ritual patterns removed (a mandatory six-step procedure, a scratchpad rule, a verify-twice rule, contradicting instructions) | [How Claude remembers your project: Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files) | Figures kept out (Q29). Q18 left the gap rows and the four ritual patterns to a row-by-row read at planning; that read was not done, and this branch adds no criteria row | Moved to [#5772](https://github.com/melodic-software/claude-code-plugins/issues/5772) (Q18) | 2026-10-01 | The next edit of the audit-instructions criteria, or the section moves |

### Caching and compaction

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Cache prices (vendor-reported): a cached read at 5% of fresh input on Opus 5.5; writes at 1.25 times input for five minutes and twice input for one hour; at 120K tokens a five-minute write of about $0.60, a read of about $0.02, a one-hour write of about $0.96 | [Pricing: Prompt caching](https://platform.claude.com/docs/en/about-claude/pricing#prompt-caching) | Kept out of repository guidance (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | The pricing table changes |
| Cache lifetime: an hour on a subscription, five minutes on an API key, a cloud provider, or a subscription drawing usage credits | [How Claude Code uses prompt caching: Which TTL each request gets](https://code.claude.com/docs/en/prompt-caching#which-ttl-each-request-gets) | Billing here is a Claude subscription (Q3). No loop cadence change; lanes follow the built-in wakeup text. The docs give the main conversation one hour on a subscription within plan usage, and subagents, workflows, in-process teammates and compaction five minutes (Q21) | NOT ADOPTED (Q21) | 2026-10-01 | Section moves |
| TTL of `claude --bg` sessions and routines (not in the post; raised at Q21) | Checked: [How Claude Code uses prompt caching: Which TTL each request gets](https://code.claude.com/docs/en/prompt-caching#which-ttl-each-request-gets), which names interactive turns, `-p` runs and Agent SDK turns but neither of these | Nothing built (Q21) | GAP (Q21) | 2026-10-01 | A docs page names their TTL |
| TTL of split-pane agent teammates (research gap G2) | Checked: [How Claude Code uses prompt caching: Which TTL each request gets](https://code.claude.com/docs/en/prompt-caching#which-ttl-each-request-gets) and [Orchestrate teams: Token usage](https://code.claude.com/docs/en/agent-teams#token-usage); only in-process teammates are named | Nothing built (Q47) | GAP (Q47) | 2026-10-01 | A docs page names their TTL |
| Expect a cache write after a pause, an effort change on some providers, fast mode's first use, an MCP connect or disconnect, a model switch, or a compaction | [How Claude Code uses prompt caching: Actions that invalidate the cache](https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache) | Phase 2 adds one pointer line to `plugins/playbooks/reference/prompt-caching.md`'s session-side section; no new cache chapter (Q15, Q44). The MCP and effort items differ from the docs; see Conflicts | ADOPTED (Q15) | 2026-10-01 | Section moves |
| Effort change on Microsoft Foundry or a custom `ANTHROPIC_BASE_URL` (research gap G3) | Checked: [How Claude Code uses prompt caching: Changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level); neither is in its keep list or its exception list | Nothing built (Q47) | GAP (Q47) | 2026-10-01 | The section names them |
| Long sessions cost more per turn (vendor-reported: a turn's cache read about $0.004 at 20K tokens and $0.03 at 150K; 30 turns about $0.90 at 150K and $0.12 at 20K) | [Manage costs: Why usage climbs in a long session](https://code.claude.com/docs/en/costs#why-usage-climbs-in-a-long-session) | Figures kept out (Q29); the section is linked in Phase 2 (Q36) | ADOPTED (Q36) | 2026-10-01 | Section moves |
| Compaction, `/compact`, `/clear` and `/autocompact` | [How Claude Code uses prompt caching: Compacting the conversation](https://code.claude.com/docs/en/prompt-caching#compacting-the-conversation); [Model configuration: Set the auto-compact window](https://code.claude.com/docs/en/model-config#set-the-auto-compact-window) | Pointer in this record; repository text follows the docs on a cold `/compact` (Q15). See Conflicts | POINTER (Q15) | 2026-10-01 | Either section moves |
| Compaction payback (vendor-reported): about $0.25 to compact at 150K tokens, about $0.025 saved per later turn, paying for itself within about ten turns | [Manage costs: Manage context proactively](https://code.claude.com/docs/en/costs#manage-context-proactively) | Kept out of repository guidance (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | Section moves |
| `/rewind` returns to an already cached prefix | [How Claude Code uses prompt caching: Rewinding the conversation](https://code.claude.com/docs/en/prompt-caching#rewinding-the-conversation) | Pointer in this record (Q15) | POINTER (Q15) | 2026-10-01 | Section moves |
| What loads before you type: CLAUDE.md under 200 lines, deferred MCP tool definitions, `/mcp` to turn off unused servers | [Manage costs: Move instructions from CLAUDE.md to skills](https://code.claude.com/docs/en/costs#move-instructions-from-claude-md-to-skills); [Manage costs: Reduce MCP server overhead](https://code.claude.com/docs/en/costs#reduce-mcp-server-overhead) | Covered by `claude-memory:audit` (CLAUDE.md line budget), `context-budget:audit` and `mcp-tools:audit`; no new startup-payload check (Q47) | COVERED (Q47) | 2026-10-01 | Either section moves |
| Fast mode (vendor-reported: up to 2.5 times faster at twice the standard price, $8 input and $40 output per million tokens); turn it on at the start of a session | [Fast mode: Understand the cost tradeoff](https://code.claude.com/docs/en/fast-mode#understand-the-cost-tradeoff); [How Claude Code uses prompt caching: Turning on fast mode](https://code.claude.com/docs/en/prompt-caching#turning-on-fast-mode) | Figures kept out (Q29); no repository surface turns fast mode on | NOT ADOPTED (Q29) | 2026-10-01 | Either section moves |
| The Batch API bills half price on input and output (vendor-reported in the post's bill table) | [Pricing: Batch processing](https://platform.claude.com/docs/en/about-claude/pricing#batch-processing) | Not used by Claude Code sessions here; nothing built (Q47) | NOT ADOPTED (Q47) | 2026-10-01 | Section moves |
| Typical spend (vendor-reported, quoting the costs doc): about $13 per developer per active day across enterprise deployments, under $30 for 90% of users; the post adds "Both figures are for current models" | [Manage costs](https://code.claude.com/docs/en/costs) (page introduction) | Not used as a per-task reference; the operator's own `/usage` history is the baseline. The post's "current models" clause is the post's own (Q29) | NOT ADOPTED (Q29) | 2026-10-01 | The page introduction changes |
| Cache hooks: a model-switch guard, an idle-gap notice near the TTL, a status line showing the cache hit share | [Status line: Prompt cache fields](https://code.claude.com/docs/en/statusline#prompt-cache-fields) | Nothing built (Q47) | NOT ADOPTED (Q47) | 2026-10-01 | Section moves |

## Measure it yourself

| Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Run `/usage` (alias `/cost`); on a subscription the dollar figure is a work measure, not a bill | [Manage costs: Using the `/usage` command](https://code.claude.com/docs/en/costs#using-the-%2Fusage-command) | The Phase 2 cost-claims rule says so in `.claude/rules/cost-claims.md` (Q28) | ADOPTED (Q28) | 2026-10-01 | Section moves |
| Run the same task on two models; note turns, output tokens and cost; do three or four tasks before concluding | [Monitoring: Token counter](https://code.claude.com/docs/en/monitoring-usage#token-counter); [Monitoring: Cost counter](https://code.claude.com/docs/en/monitoring-usage#cost-counter) | Phase 4 adds a two-session `compare` action to `plugins/claude-ops/skills/observability/`: tokens by type, cache writes as their own type, split by model and effort (Q22). Its context line links the monitoring docs first and this post section as a correlate, with no task count (Q40) | ADOPTED (Q22, Q40) | 2026-10-01 | Either section moves |
| Per-request cost events can undercount (not in the post; open upstream as [anthropics/claude-code#98193](https://github.com/anthropics/claude-code/issues/98193)) | [Monitoring: API request event](https://code.claude.com/docs/en/monitoring-usage#api-request-event); [Monitoring: Cost monitoring](https://code.claude.com/docs/en/monitoring-usage#cost-monitoring) | The Phase 4 compare reconciles each session's `api_request` totals against `claude_code.cost.usage` and names #98193 when events fall short (Q7) | ADOPTED (Q7) | 2026-10-01 | #98193 changes state, or either section moves |
| For a team, use the Claude Code Analytics API and the Usage and Cost API | [Claude Code Analytics API](https://platform.claude.com/docs/en/manage-claude/claude-code-analytics-api); [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api) | Nothing built; billing here is a subscription (Q3, Q47) | NOT ADOPTED (Q47) | 2026-10-01 | Either page moves |
| Try the effort ladder: one hard task at medium then high, one mechanical task at low | [Model configuration: Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level) | The Phase 4 compare splits by effort (Q22) | ADOPTED (Q22) | 2026-10-01 | Section moves |
| Reading a session: low cache share, much output on a small change, total input many times the conversation size | [Manage costs: Prompt cache statistics](https://code.claude.com/docs/en/costs#prompt-cache-statistics) | No cache-miss triage built; the docs' likely-cause text on the `Prompt cache (main)` line covers the first check (Q47) | NOT ADOPTED (Q47) | 2026-10-01 | Section moves |

## Keep in mind

The post's closing list restates its sections, so it carries no rows of its own. Each line maps to a
row above: medium for well-scoped work and raising to high (effort ladder); a way to check work
(verification target); plan mode for changes that span files (see Conflicts); keeping the cache on
an effort change (effort and caching rows); switching to Fable 5.1 (move-up row); search and
log-reading subagents on Sonnet or Haiku with code edits on Opus 5.5 (Q20 rows and Conflicts);
keeping a session moving (cache lifetime); `/clear` and `/compact` (compaction row); and comparing
`/usage` on each model (Measure it yourself). The closing request to send `/feedback` when limits
do not go further belongs to the plan-claims row.

## Conflicts

Each row names two official sources. "Repo follows" is the side this repository's text takes.

| Post says | Docs say | Second official source | Repo follows | Checked | Recheck trigger |
|---|---|---|---|---|---|
| Keep code edits on Opus 5.5; move down to Sonnet or Haiku only for lookups | [Manage costs: Choose the right model](https://code.claude.com/docs/en/costs#choose-the-right-model): Sonnet handles most coding tasks well; reserve Opus for complex decisions | [How Claude Code works: Models](https://code.claude.com/docs/en/how-claude-code-works#models) says the same; [`opusplan`](https://code.claude.com/docs/en/model-config#opusplan-model-setting) puts execution on Sonnet | The docs' split: Sonnet for well-scoped coding, Opus for complex work (Q20, Q41). Unrouted dispatch keeps `opus`; the reason is in Decisions and follow-ups | 2026-10-01 | Either docs section changes its model advice |
| The effort picker labels xhigh "hard problems" | [Model configuration: Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level) gives `max` for hard problems you want Claude to work through without you | [Effort: Recommended effort levels for Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/effort#recommended-effort-levels-for-claude-opus-5-5) recommends an effort sweep rather than a fixed level | The docs table (Q9) | 2026-10-01 | Either section changes |
| Move to Fable 5.1 when Opus 5.5 at xhigh hits the same problem twice | [Choosing the right model: Option 2](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model#option-2-start-capability-first): move to Fable 5.1 when evals at xhigh or max still fall short | [Models overview](https://platform.claude.com/docs/en/models/overview) says the same for Opus 5.5 at higher effort | The docs' wording; the "twice" count is the post's (Q30) | 2026-10-01 | Either page changes |
| Connecting or disconnecting an MCP server causes a cache write | [How Claude Code uses prompt caching: Connecting or removing an MCP server](https://code.claude.com/docs/en/prompt-caching#connecting-or-removing-an-mcp-server): with tools deferred, a mid-session change keeps the cache; only tools loaded upfront invalidate it | [MCP: Scale with MCP tool search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search) defines when tools are deferred | The docs, qualified by tool-search state (Q15) | 2026-10-01 | Either section changes |
| An effort change misses the cache on Bedrock, Google Cloud's Agent Platform, or a gateway | [How Claude Code uses prompt caching: Changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level) names the Claude apps gateway, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` and a HIPAA configuration, and not generic gateways | [Model configuration: Set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level) links that section for the cache warning | The docs' list (Q15); Foundry and custom base URLs stay open (G3) | 2026-10-01 | The prompt-caching section changes its list |
| A cold `/compact` reads the whole conversation and writes it back to the cache, about $0.75 at 150K tokens (vendor-reported) | [How Claude Code uses prompt caching: Compacting the conversation](https://code.claude.com/docs/en/prompt-caching#compacting-the-conversation): the summarization request reprocesses the full history as uncached input | [Manage costs: Why usage climbs in a long session](https://code.claude.com/docs/en/costs#why-usage-climbs-in-a-long-session) calls compacting a large context itself a large request, with no write-back | The docs' wording, no figure (Q15). Whether the cold request bills as a cache write stays open (research gap G1) | 2026-10-01 | Either section changes, or a docs page states how the cold request bills |
| The receipt has "the three lines /usage shows for a session" | [Manage costs: Using the `/usage` command](https://code.claude.com/docs/en/costs#using-the-%2Fusage-command) shows input, output, cache read and cache write per model | [How Claude Code uses prompt caching: Check cache performance](https://code.claude.com/docs/en/prompt-caching#check-cache-performance) reports cache writes and cache reads as separate counts | The docs (Q47) | 2026-10-01 | Either section changes |
| A model named in a subagent's definition overrides `CLAUDE_CODE_SUBAGENT_MODEL`; a subagent with no model setting runs on the main model unless the variable is set | [Create custom subagents: Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model) puts the per-invocation parameter first, and says the variable alone does not move the built-in Explore and Plan subagents | [Create custom subagents: Run every subagent on one model](https://code.claude.com/docs/en/sub-agents#run-every-subagent-on-one-model) needs `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` for that | The docs' order (Q5) | 2026-10-01 | Either section changes |
| Opus 5.5 "always thinks before it replies", and Claude Code "only shows you a summary" | [Model configuration: Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking): thinking cannot be turned off, the model decides per step how much to think, and interactive Anthropic API sessions receive redacted thinking by default | [Thinking: Controlling thinking display](https://platform.claude.com/docs/en/build-with-claude/thinking#controlling-thinking-display) | The docs' wording (Q30) | 2026-10-01 | Either section changes |
| Start changes that span files in plan mode | [Best practices: Explore first, then plan, then code](https://code.claude.com/docs/en/best-practices#explore-first-then-plan-then-code) gives several conditions and a skip rule | [Manage costs: Work efficiently on complex tasks](https://code.claude.com/docs/en/costs#work-efficiently-on-complex-tasks) says plan mode for complex tasks | The best-practices conditions (Q30) | 2026-10-01 | Either section changes |
| Run `/claude-api prompt-audit` to check your Claude Code setup | [How Claude remembers your project: Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files) names `/doctor prompt-audit` for instruction files | [Skills: Work on Claude API projects](https://code.claude.com/docs/en/skills#work-on-claude-api-projects) scopes `/claude-api prompt-audit` to prompts, skills and tool descriptions | Both commands, each for its documented scope (Q8) | 2026-10-01 | Either section changes |
| Not in the post: the version floor for `promptCacheTtl`, `subagentPromptCacheTtl` and the `/usage` Loops rows | [How Claude Code uses prompt caching: Choose the TTL yourself](https://code.claude.com/docs/en/prompt-caching#choose-the-ttl-yourself) and [Manage costs: Plan usage breakdown](https://code.claude.com/docs/en/costs#plan-usage-breakdown) say v2.1.242 | The [changelog](https://code.claude.com/docs/en/changelog) has no 2.1.242 entry and adds both settings in 2.1.243 | v2.1.242, as the docs state (Q33) | 2026-10-01 | The changelog gains a 2.1.242 entry, or either docs section changes the floor |

## Decisions and follow-ups

Stated deviations from the docs and precedent (Q38):

- **Rows are implemented in this record's own pull request (Q43).** The precedent
  `docs/upstream/claudedevs-cost-performance.md:19` has every plain ADOPT row point at a filed work
  item. Here the user chose to build the record, the small rows and the observability comparison
  on this branch; only Q35 gets a work item.
- **Unrouted dispatch keeps `opus` (Q20).** [Manage costs: Choose the right model](https://code.claude.com/docs/en/costs#choose-the-right-model)
  puts most coding on Sonnet. `implementation:implementer` stays on `opus` for any phase the plan
  does not mark `sonnet`. Reasons: a lane with no plan has no scope check, so it fails safe on the
  stronger model; and on some providers the `sonnet` alias resolves to an older Sonnet unless
  `ANTHROPIC_DEFAULT_SONNET_MODEL` is set ([Model configuration: Model aliases](https://code.claude.com/docs/en/model-config#model-aliases)),
  so dispatch falls back to `implementer` there.

Q42 outcome, from the plan approval gate: **keep**. These 12 rows of
`plugins/claude-config/skills/audit-instructions/reference/criteria.md` overlap `/doctor
prompt-audit` and keep their own text: I1, I5, I8, I8-c, I8-e, I9, I10, I20, I25, I26, I28, I31.
The verdict is complementary, as recorded in
`plugins/claude-config/skills/audit-instructions/reference/native-doctor.md` ("Why the verdict is
complementary", [#5387](https://github.com/melodic-software/claude-code-plugins/pull/5387)): the
model cannot invoke `/doctor`, so a pointer row would turn a finding the audit reports into one only
a person can produce, which breaks report-only and unattended runs. The deterministic pre-scan
stays as the wrapper.

Owner rows (Q46: every item in a file another session owns has a confirmed doer):

| Item | Ledger | Doer | Pull request |
|---|---|---|---|
| Two "default high" effort lines point at model-config | Q19 | Building With Claude Sonnet 5.5 | Landed: [#5759](https://github.com/melodic-software/claude-code-plugins/pull/5759) (`6b0802bdd`) |
| Boris superseded lines and the `foundations.md` amendment | Q33 | Building With Claude Sonnet 5.5 | Landed: [#5759](https://github.com/melodic-software/claude-code-plugins/pull/5759) (`6b0802bdd`) |
| `criteria.md` I17-b: the provider-scoped effort-cache exception | Q32 | Prompting Sonnet 5.5 | PR: pending (Gate S1) |
| docpage-digest: blog-apparatus category, exact-byte write route, pin freeze applying to the parent | Q10, Q11, Q12 | Prompting Sonnet 5.5 | PR: pending (Gate S1) |
| Sonnet 5.5 model-adaptation chapter; `opus-5-5.md` unchanged | Q37 | Prompting Sonnet 5.5 | PR: pending (Gate S1) |
| The #5678 model-tier points in `docs/plugin-philosophy.md` | Q20 | Prompting Sonnet 5.5 | PR: pending (Gate S1) |
| `docs/upstream/claude-code.md` `_FORCE` row; the two queued posts | Q39 | Released to this branch (Phase 1; Phase 7) | This branch |
| `prompts/loops/loop-lane-prompts.md` tier qualification | Q20 | Released to this branch by Building (Phase 5) | This branch |
| `scoped-implementer` effort pin at medium | Q41 | Released to this branch by Prompting (Phase 5) | This branch |

Filed:

- [#5763](https://github.com/melodic-software/claude-code-plugins/issues/5763), the parent issue
  this branch closes (Q45).
- [#5764](https://github.com/melodic-software/claude-code-plugins/issues/5764), sub-issue: run
  independent plan phases in parallel by default, on subagents for focused work and on agent teams
  only where the user enabled them and the workers must coordinate; the one-worker pilot before a
  wide fan-out stays (Q35).

Decisions on this branch:

- Q1: a third `docs/upstream/` record for this post, then the adopted rows are built (shape and
  delivery: Q43, Q45).
- Q2: mechanism choices were made at planning, not in the interview.
- Q6: Phase 3 amends research outcome-gate row 7 in `plugins/discovery/skills/research/SKILL.md`
  so a claim labelled MEDIUM or LOW and listed as a gap is not an accepted claim, after checking
  the row's other callers.
- Q34: Phase 7 queues "Using Claude Code: Spending your effort" and "Lessons from building Claude
  Code: Prompt caching is everything" in the docpage-digest queue as recorded, not run. Their two
  standfirsts are cited only as vendor claims.
- Q45: one draft pull request, a commit per area, closing #5763. It also fixes the
  instruction-placement index generator so eval fixtures stay out of the generated `AGENTS.md`
  rules table.
- Q33, the low-severity bundle: the session-flow observer keeps its dated `claude-haiku-4-5`
  default; v2.1.242 is kept (see Conflicts); `docs/upstream/claudedevs-cost-performance.md:157`
  keeps its dated count of 13; the cosmetic digest wording is left as is. The evals USD anchors in
  `plugins/evals/skills/plugin-eval/SKILL.md:139-146` were measured on 2026-09-12 and 2026-09-13,
  before the Opus 5.5 price change, and carry no recheck trigger; this record notes them with the
  trigger "the default model or a list price changes". The listing budget check scans skill
  descriptions only, so nothing here counts against it.
- Withdrawn and replaced during the interview: Q16 by Q22, Q23 by Q35, Q27 by Q36, Q31 by Q37.
  Q41 moved Q20 onto this branch.
- Research gaps (Q47): G1 is in Conflicts; G2 and G3 are GAP rows under caching; G4, the
  Claude Code client source, is not public, so no rung reads it; G5 is the evidence standing in
  [Source and verification](#source-and-verification).
