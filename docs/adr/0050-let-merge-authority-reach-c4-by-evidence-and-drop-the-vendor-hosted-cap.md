# Let merge authority reach C4 by evidence, and drop the vendor-hosted cap

- Status: accepted
- Date: 2026-10-03

## Context

Three absolutes cap what an unattended lane may merge:

- **C4 never.** Structural work (refactors, migrations, contract changes) needs human review and
  human merge "always" (`plugins/autonomy/reference/guardrails/work-classes.md:35-37`). The
  loop-lane convention repeats it: "no rung, no tracked config, and no invocation argument ever
  reaches them" (`docs/conventions/loop-lane/README.md:50-52`).
- **C5 never.** Untrusted-provenance work is human-merged under the same clause.
- **Vendor-hosted executors cap at human-gated merge**, whatever the work class
  (`plugins/autonomy/reference/trigger-dispatch.md:200-201`).

The operator's rule for the PR pipeline is that no rule is absolute without evidence for it. Each
cap was reviewed against that rule.

## Decision

1. **Drop the vendor-hosted cap.** Merge authority comes from the work class, the evidence gates and
   the repository's configured rung, not from where the executor runs. The lanes built on
   claude-code-action are self-operated in any case.
2. **Make C4 promotable.** A repository may raise its merge rung to C4 only through a merged change
   to its pipeline config, and a C4 merge then needs all of:
   - three independent checkers agreeing on the final commit, including a Claude judge and a Codex
     judge;
   - a post-merge failure response decided for that repository (revert or fail forward by change
     type), so a bad structural merge has a known remedy before it happens;
   - every gate that a C3 merge needs.
3. **Keep C5 human.** Untrusted provenance has no evidence predicate a checker can satisfy, so no
   rung reaches it.

The baseline rung stays C2 plus a scripted diff check, and every rung rises only by a human-merged
config change and falls automatically after a post-merge failure.

## Alternatives considered

- **Keep all three caps.** Rejected: the C4 and vendor-hosted caps are stated as absolutes without
  evidence that no gate could ever be enough, and they block repositories that want to earn more
  autonomy.
- **Make C5 promotable too.** Rejected: the risk in C5 is who wrote the change, which more checkers
  reading the same text do not reduce.
- **Promote C4 with a single AI judge.** Rejected: structural changes are where one model's blind
  spots cost most, so the rule needs independent judges from two vendors.

## Consequences

- `work-classes.md`, `trigger-dispatch.md` and the loop-lane autonomy ladder need matching changes.
  Until they land, those documents and this record disagree.
- The pr-pipeline schema offers no C4 rung until those changes land, so no repository can configure
  one early.
- C4 promotion depends on the open post-merge failure-response decision: no repository can raise
  to C4 before it has one.
