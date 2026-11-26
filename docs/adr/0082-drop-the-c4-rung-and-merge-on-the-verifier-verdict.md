# Drop the C4 rung and merge on the verifier verdict

- Status: accepted
- Date: 2026-10-22
- Amends: [ADR 0050](0050-let-merge-authority-reach-c4-by-evidence-and-drop-the-vendor-hosted-cap.md),
  Decision 2

## Context

ADR 0050 Decision 2 made C4 promotable: a repository could raise `merge.rung` to C4 through a merged
config change, with three agreeing checkers and a decided post-merge response.

The owner later dropped the C4 rung
([decision on #6140](https://github.com/melodic-software/claude-code-plugins/issues/6140#issuecomment-6293779081)).
Work classes are retired for the pr-merge lane, which reads no class label and merges on the verifier
verdict. #8668 aligned the autonomy contract, the loop-lane convention and the pr-pipeline README
with that decision, so they now disagree with Decision 2 of the accepted ADR.

## Decision

1. **No rung reaches C4.** `merge.rung` stays `off`, `C2` or `C3`. No merged config change, checker
   count or post-merge response makes a C4 rung available, so ADR 0050 Decision 2 no longer applies.
2. **The pr-merge lane merges on the verifier verdict.** It reads no work-class label. What a PR may
   merge on is the verifier's verdict on the final commit, within the configured rung.
3. **ADR 0050 Decisions 1 and 3 stand.** The vendor-hosted cap stays dropped, and C5 stays human. Their
   outcomes stand; where they cite the work class as the source of merge authority, read that as the
   verifier verdict within the configured rung, since the pr-merge lane no longer reads a class.

## Alternatives considered

- **Keep C4 promotable.** Rejected: the owner dropped the rung, and the work classes it depended on
  are retired for the pr-merge lane.
- **Edit ADR 0050 in place.** Rejected: an accepted record keeps its text, and only its status line
  points at the successor.

## Consequences

- The autonomy contract, the loop-lane convention and the pr-pipeline README already match this
  record (#8668). Only ADR 0050 Decision 2 disagrees with them, and its status line now points here.
- The "post-merge failure-response decision" ADR 0050 listed as a precondition for C4 no longer gates
  any rung.
