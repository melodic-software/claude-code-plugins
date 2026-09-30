# Record the skill interop decisions and conformance gates

- Status: accepted
- Date: 2026-09-29

## Context

Four questions about how this marketplace's skills interoperate with the Agent Skills
specification and with other tools stayed open: whether skills carry the optional
`compatibility` field, whether frontmatter needs a rule, whether to guard against compaction
dropping a skill, and whether to add a project `.agents/skills` root. The owner decided all four
by taking the first option on each. This record keeps the decisions and their reasons in one
place.

## Decision

**Compatibility field: no skill carries it, and nothing requires it.** The specification says most
skills do not need the field. 0 of 303 skills carry it. `check-skill.sh` treats a missing field
as a pass and length-checks a present one (1-500 characters), so a skill that needs it later can
add it without a gate change.

**Frontmatter: no rule.** Frontmatter is loader metadata only. 0 of 305 skills put instructions
in frontmatter beyond `description`. The Claude Code skills reference does not say whether
frontmatter is stripped from the content Claude reads, so a rule would enforce a guess.

**Compaction: accept the runtime behavior, add no check.** The skills reference says
auto-compaction re-attaches each skill's most recent invocation, up to 5,000 tokens each within a
25,000-token shared budget. The remedy is to invoke the skill again, and a static check cannot
predict what one session compacts.

**`.agents/skills` root: do not add it now.** Harness verdict row 5 in
[`docs/upstream/aihero-course.md`](../upstream/aihero-course.md) is REFUTED for
`~/.agents/skills`: Claude Code does not read it. A re-run on Claude Code 2.1.284 did not list a
project `.agents/skills` probe either. A root Claude Code does not read would serve other tools
only, at the cost of a second copy to keep in step.

## Conformance and gates

| Rule | Violations | Gate |
|---|---|---|
| Name rules | 0 | `check-skill.sh` check 1 accepts a missing `name` field, so a skill without one passes |
| Body under 500 lines | 0 | Checked |
| Description 1-1024 characters | 1 baselined in `scripts/skill-description-cap-baseline.txt` | Enforced by `check-skill.sh` check 2b |
| Body under 5,000 tokens (recommendation) | 54 skills exceed it | None. Restructuring is out of scope |

## Consequences

The spec [`docs/specs/agent-doc-surfaces.md`](../specs/agent-doc-surfaces.md) points here for the
`.agents` decision. Revisit the fourth decision when a Claude Code release documents a project
`.agents/skills` path and a probe lists it. The 5,000-token recommendation stays advisory until
someone takes on splitting the 54 bodies.
