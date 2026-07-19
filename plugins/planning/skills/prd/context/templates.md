# PRD templates — three tiers

All three tiers cover the same seven required sections. Tier governs verbosity, not section presence. Loaded on demand by `/prd` once tier is chosen.

**Prototype snippet exception:** if a logic prototype (e.g. `/prototype:pressure-test`, if installed) produced a snippet that encodes a design decision more precisely than prose (state machine, reducer, schema, type shape), inline the decision-rich parts in the Open questions section and note it came from a prototype. The PRD defers implementation details to `/planning:plan`, but prototype-validated design constraints are product-level — they belong here.

---

## Tier 1 — Thin one-pager

Use when: small feature, single team owns it, low ambiguity, fast lock. ~½ page.

Sections collapse to one line each. The point is to write down what would otherwise stay in someone's head, not produce a polished artefact.

```markdown
---
status: draft
tier: one-pager
created: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
updated: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
---

# PRD — <feature name>

## Problem
<1-2 sentences. Whose problem, what they currently do instead.>

## Goals
- <outcome statement>
- <outcome statement>

## Non-goals
- <thing explicitly out of scope>

## Users
<one persona, one sentence. Optional 1 user story.>

> As a <role>, I want <action>, so that <outcome>.

## Success metrics
- <metric> reaches <threshold> within <window>

## Dependencies / risks
- <dependency or risk> — <mitigation or owner>

## Open questions
- <question that /planning:plan needs answered>
```

### Example — "Add gig calendar to dashboard"

```markdown
---
status: draft
tier: one-pager
created: 2026-05-02T14:30:00Z
updated: 2026-05-02T14:30:00Z
---

# PRD — Gig calendar on artist dashboard

## Problem
Artists track upcoming gigs in spreadsheets and Google Calendar separately from the platform. Conflicts with rehearsals and song-prep deadlines aren't visible until the day-of.

## Goals
- Artists see all upcoming gigs at a glance on their dashboard
- Conflicts with rehearsals or song-prep deadlines surface visually

## Non-goals
- Booking workflow (existing tool)
- Calendar export to external apps (follow-up)

## Users
Solo and band artists who play 2+ gigs/month.

> As a band-leader, I want to see this month's gigs alongside song-prep deadlines, so that I can spot prep gaps before the gig.

## Success metrics
- 60% of weekly-active artists open the calendar widget within 14 days of launch
- Self-reported "missed a prep deadline" rate (in monthly survey) drops by half within 60 days

## Dependencies / risks
- Reuses the existing `Calendar` domain term — confirm semantics with the owning module's vocabulary
- Risk: overlapping with planned rehearsal-scheduling feature → coordinate with that PRD

## Open questions
- Show full month or rolling 14-day window? (/planning:plan to evaluate based on data density)
```

---

## Tier 2 — Consumer feature

Use when: user-facing app feature with metrics, 1-2 user stories, risk surface. ~1 page.

Full sections, full paragraphs. This is the default for most consumer-facing features.

```markdown
---
status: draft
tier: consumer-feature
created: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
updated: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
---

# PRD — <feature name>

## Problem
<1-2 paragraphs. What is broken, missed, or unmet for users today. Quantify if possible — how often, how many, how painful. End with the cost of not solving it.>

## Goals
- <Outcome-level. "Users can <X>" or "<metric> moves from A to B".>
- <Outcome-level.>
- <Outcome-level.>

## Non-goals
- <Explicit out-of-scope item with one-line reason.>
- <Explicit out-of-scope item.>

## Users
<Primary persona — who they are, what they do today, what they'd do differently with this feature. 1-2 paragraphs.>

### User stories

Enumerate all significant user journeys — err on completeness over brevity. Every flow a product reviewer might ask about should be a story. Aim for exhaustive coverage of the feature surface.

1. **As a <role>**, I want <action>, **so that** <outcome>.
2. **As a <role>**, I want <action>, **so that** <outcome>.
3. ...

## Success metrics
| Metric | Baseline | Target | Window |
|--------|----------|--------|--------|
| <name> | <today's value or "n/a"> | <target value> | <e.g. 30 days post-launch> |
| <name> | <baseline> | <target> | <window> |

Each metric must have a measurement window and a numeric or qualitative threshold. "Increase engagement" without a number does not belong here — push it to **Open questions**.

## Dependencies / risks
- **Dep**: <outside-team dependency> — <owner / status>
- **Risk**: <top risk> — <mitigation or accepted with reasoning>
- **Risk**: <top risk> — <mitigation>

## Open questions
- <Question /planning:plan needs answered before a plan is realistic.>
- <Question that needs market or user-research data before locking — defer to research.>
```

### Example shape — "Lyric search with fuzzy matching"

Same structure as above, applied to a music-platform feature. Skip body — agent fills via frontier-rounds Q&A. Key tier-2 differences from tier-1:

- Multiple user stories (1-2 minimum) covering distinct personas or distinct flows
- Metrics table with baseline + target + window (not just threshold)
- Risks separated from dependencies; each risk has a named owner or accepted-with-rationale note
- Problem section quantifies, not just describes

---

## Tier 3 — B2B / internal

Use when: internal tooling, B2B feature, or anything with stakeholders, compliance, integration, rollout, change-management concerns. ~2 pages.

Full sections + three additional sections (stakeholders, rollout, compliance/integration). Tier 3 is heavier because internal/B2B features fail when alignment misses, not when the feature is wrong.

```markdown
---
status: draft
tier: b2b-internal
created: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
updated: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
---

# PRD — <feature name>

## Problem
<2-3 paragraphs. What is broken for internal users / B2B customers today. Quantify cost: support tickets per week, hours per cycle, error rate, audit findings, churn signals. Tier-3 PRDs justify investment; problem section carries that weight.>

## Goals
- <Outcome-level statement.>
- <Outcome-level statement.>
- <Outcome-level statement.>

## Non-goals
- <Out-of-scope item with one-line reason.>
- <Out-of-scope item.>
- <Out-of-scope item.>

## Stakeholders
| Role | Name / team | Stake |
|------|-------------|-------|
| Sponsor | <team or role> | <decision authority> |
| Primary user | <team or role> | <day-to-day usage> |
| Affected user | <team or role> | <indirect impact> |
| Reviewer | <team or role> | <sign-off scope — security, compliance, ops> |

## Users
<Internal personas or B2B customer personas. 2-3 paragraphs covering each affected role and how their workflow changes.>

### User stories

Enumerate all significant user journeys across every affected role — err on completeness over brevity. B2B/internal features often have more distinct user flows than consumer features (admin, integrator, end-user, auditor paths).

1. **As a <internal role>**, I want <action>, **so that** <outcome>.
2. **As a <internal role>**, I want <action>, **so that** <outcome>.
3. **As an <integrator / admin>**, I want <action>, **so that** <outcome>.
4. ...

## Success metrics
| Metric | Baseline | Target | Window | Owner |
|--------|----------|--------|--------|-------|
| <name> | <baseline> | <target> | <window> | <team> |
| <name> | <baseline> | <target> | <window> | <team> |

Each metric named with owner — "who watches the dashboard" matters in tier-3.

## Dependencies / integrations
- **Internal**: <upstream/downstream service or team> — <coupling> — <owner>
- **External**: <vendor, API, regulator> — <coupling> — <SLA / contract>
- **Integration**: <existing system this must coexist with> — <data flow direction>

## Compliance / risks
- **Compliance**: <regulation, audit, data classification> — <treatment>
- **Risk**: <top risk with internal/B2B framing — change management, downtime tolerance, rollback> — <mitigation>
- **Risk**: <risk> — <mitigation>

## Rollout
- **Phasing**: <e.g. internal pilot → 10% customers → 100%>
- **Feature flag / gate**: <name + decommission criteria>
- **Backout plan**: <how to revert if metrics regress>
- **Communication**: <who is notified, when, with what runbook>

## Open questions
- <Question /planning:plan needs answered.>
- <Question for sponsor / compliance / legal.>
- <Question that needs research before locking.>
```

### Example shape — "Admin role overrides in B2B portal"

Same structure as above, applied to a B2B internal feature. Tier-3 differences from tier-2:

- Stakeholders table is required and named (not just "the admin team")
- Compliance section explicit even when no regulation applies — say so ("no compliance impact, low data sensitivity")
- Rollout section with phasing, flag, backout, comms — internal/B2B features are usually more change-managed than consumer ones
- Metrics table includes owner column

---

## Tier selection cheat sheet

If `/prd` is invoked without an explicit tier, use this to drive the tier prompt (card only under the `use_ask_user_question` opt-in; numbered prose otherwise):

| Question | Tier 1 (one-pager) | Tier 2 (consumer-feature) | Tier 3 (B2B-internal) |
|----------|--------------------|---------------------------|------------------------|
| Single team owns end-to-end? | Yes | Usually | Often no — multiple teams |
| Stakeholders beyond the team? | No | Maybe (PM, design) | Yes (sponsor, sec, ops, compliance) |
| User-facing in consumer app? | Maybe | Yes | Sometimes — internal tools too |
| Compliance / audit / regulated data? | No | Rarely | Often |
| Phased rollout / feature flag? | No | Sometimes | Yes |
| Verbosity | ½ page | 1 page | 2 pages |

When in doubt: pick the lower tier. Sections are present in all three — tier governs how much you write, not what's missing.
