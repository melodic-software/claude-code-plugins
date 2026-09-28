# Unhobble durable state and decide composition

Park for [#4094](https://github.com/melodic-software/claude-code-plugins/issues/4094).

## Decision

**Do not rewrite `/claude-config:unhobble` state, strip rules, or `decide` in
this session.** The issue is one `claude-config` version bump covering nine
must-fix criteria plus UX helpers. That is a skill rewrite with an eval per
criterion. Plugin ablation stays #4095, parked separately.

**Claim:** The first cloud run's gaps (ephemeral state, absolute host paths,
changelog-parity collision, a carve-out attributed to an official page) are
real follow-ups. They are not a small correction on top of the current skill.
**Basis:** #4094 acceptance criteria and the constraint that the set ships as
one version bump. Experiment evidence is PR #4090. Official settings behavior
used by the child (#4095) is the
[settings reference](https://code.claude.com/docs/en/settings-reference)
`enabledPlugins` precedence, fetched 2026-09-28. The carve-out fix is to stop
citing an official exemption the issue says no official page states.
**As of:** 2026-09-28.
**Recheck:** An operator funds the single `claude-config` bump, with evals for
each must-fix row, human-gated mutations unchanged.

## What this close is not

Not a decision that the current `${CLAUDE_PLUGIN_DATA}` state home is fine.
It is a decision not to move it until that bump is funded.
