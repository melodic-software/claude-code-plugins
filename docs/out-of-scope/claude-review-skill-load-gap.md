# claude-review: skill invocation returns no content

Recorded park for
[#4306](https://github.com/melodic-software/claude-code-plugins/issues/4306).

## Decision

**Parked, known gap.** This repository does not restore a skill-degrade
guard and does not own a further harness patch. The Skill-tool grant lives
in `melodic-software/ci-workflows` and shipped in v0.29.1. Callers here are
already pinned to that release. Confirmation that an ordinary consumer PR
loads `/review:code-review`, and any remaining work to fail the lane when
the skill does not run, stay unpaid.

**Claim:** the "Execute skill: review:code-review with no further content"
failure was a headless `Skill` permission denial in the reusable, not a
defect in this marketplace's `review` plugin. v0.29.1 appends
`--allowedTools "Skill(<plugin-command>)"`. This repo's callers use
`claude-review.yml@0d3e6a6f3851cf678f82fa9a8a17f10faa909ac9` (v0.29.1).
The deleted skill-degrade guard is not restored, so a later Skill miss can
still fall back to a manual review and stay green.
**Basis:** #4306 comments (2026-09-25 root cause and v0.29.1 ship in
ci-workflows#625); #4492 re-pin (merged; "closed separately once a lane
run on v0.29.1 is verified"); ADR 0038 addendum deleting
`scripts/verify-claude-review-skill.sh`. Issue still OPEN pending an
ordinary-PR confirmation run.
**As of:** 2026-09-28.
**Recheck:** a non-draft PR's `review / review` job on a v0.29.1+ pin shows
`Skill(review:code-review)` in allowedTools and a skill-body load
(`Launching skill: review:code-review` or equivalent), and a maintainer
unparks #4306; or the reusable starts failing the job when the configured
plugin command does not run.

## What stays

- Thin callers in `.github/workflows/claude-review.yml` and
  `claude-security-review.yml`, pinned to ci-workflows v0.29.1.
- ADR 0038: every push reviewed, drafts skipped, status check advisory,
  `ci-status` the only required check.
- The `review` plugin skill (`disable-model-invocation: false`).

## What does not ship

- Rebuilding `scripts/verify-claude-review-skill.sh` or matching "skill
  invocation errored" in review bodies.
- A harness patch in this repository. Further grant or fail-closed work
  belongs in ci-workflows.
- Closing #4306 on the pin alone. The thread asked for an ordinary-PR
  confirmation run.

## Rationale

- Plugin install already succeeded in the failing runs. Frontmatter is
  fine. The denial was `Skill` absent from `allowedTools`.
- The grant is composed in the reusable after the caller's `claude-args`,
  so a caller cannot drop it. That fix is not this repo's to repeat.
- ADR 0038 removed the evidence guards. Restoring one here would re-open a
  retired bookkeeping surface without a funded decision.

## Revisit when

- An ordinary v0.29.1+ lane run confirms the skill body loaded, or
- ci-workflows fails the job when the configured plugin command does not
  run, or
- a maintainer unparks #4306 to restore an in-repo degrade guard.

## Prior requests

- #4306 (2026-09-28): org review lane fallback; drain shipper parks the
  unpaid confirmation and documents the known green-on-fallback gap.
  Related: #4093, #4124, #4492, ci-workflows#625.
