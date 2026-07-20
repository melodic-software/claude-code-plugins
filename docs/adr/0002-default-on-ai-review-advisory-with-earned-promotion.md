# Default-on AI review: advisory lanes with earned promotion to blocking

- Status: accepted (interim — pending the #509 enforcement design ruling)
- Date: 2026-07-20

## Context

Boris Cherny's step-2 posture ("Steps of AI Adoption", Jul 16 2026) names "Automated code
review and security review are on by default"; the AI-adoption-ladder residue items #696
(default-on review decision + wiring) and #509 (no dedicated security-review pass) carried
the two open choices: promote the LLM review lane from advisory to blocking or keep it
advisory with a recorded promotion trigger, and where a dedicated security pass runs.

Evidence in hand at decision time: the LLM code-review lane (`claude-review` reusable
workflow, consumed by this repo's caller) already auto-invokes on every PR event —
default-on is satisfied for invocation; the open question was gating. #618 documents the
noise cost of advisory bot threads blocking merges on every PR; the WP5 guardrail work
ratified the verification-promotion discipline (a gate flips from advisory to blocking only
on demonstrated precision — an earned flip with a ratified record, trust before scale).
2026-07-20 transcript mining (548 real permission prompts; #697's evidence) reinforced that
review friction compounds fast at fleet scale.

## Decision

1. **Both AI review lanes are DEFAULT-ON and ADVISORY**: the general code-review lane on
   every PR (existing caller), and the dedicated security-review lane
   (`claude-security-review` reusable workflow, ci-workflows) wired by this repo's caller
   with a PATH FILTER over security-sensitive surfaces — workflows, scripts, hooks, shell,
   and permission/settings configuration. Path filtering is the scope control that keeps
   default-on affordable in a doc-heavy repo: most PRs are prose and get the general lane
   only.
2. **Promotion to blocking is earned, not assumed**: either lane flips to a required gate
   (security: blocking on CRITICAL findings) only after its precision is proven over a
   sustained window, recorded as a reviewed change citing that evidence — mirroring the
   WP5 verification-promotion discipline. No calendar-based flip.
3. **Severity vocabulary**: the security lane reports CRITICAL/IMPORTANT/SUGGESTION with a
   confidence axis, matching the review-toolkit convention.

This is the interim posture pending #509's enforcement design session (operator-deferred,
2026-07-19): how the pipeline enforces and evidences that a security pass ran on every PR is
that session's question, and it may promote the security lane to a required gate on its own
terms without a further precision window.

## Revisit triggers

- The security lane's findings prove precise over a sustained window → open the promotion
  change (blocking on CRITICAL) citing the evidence.
- The general lane's advisory threads measurably gate merges again (#618's class) → tune
  scope before considering demotion.
- ci-workflows ships a release changing either reusable workflow's contract → re-pin the
  callers through the ordinary Dependabot/SHA-bump path.
