# Gotchas

Failure patterns this skill exists to prevent, and the two that bite its own operation.

## Confident storytelling

The dominant failure. A plausible narrative assembled from thin evidence reads better than an honest
patchwork, so it wins unless something stops it. A claim with no citation belongs under
*What we can reasonably infer* or *Competing hypotheses*, never under *What we found*.

The tell is a sentence that would survive unchanged if the evidence behind it were deleted.

## Citing the code as evidence for its own intent

"Retries three times because there is a retry loop with a limit of three" restates the mechanism and
calls it a motive. Motivation comes from a source outside the implementation, or it is labelled
inference — and here, code shape is not even that: it leaves the scale and is recorded as a gap.

The subtle version is a named constant. A literal `128 * 1024` and a convention elsewhere in the
codebase feel like an explanation. They are a hypothesis at best.

## Recency bias

The most recent commit is not the authoritative one. Current shape is usually accretion — a decision,
a partial revert, a workaround, a cleanup that preserved the workaround without knowing why. Trace
back past the last change that touched the line.

## Sycophantic agreement

When the person asking supplies a theory — "I assume this was for performance?" — that is a
hypothesis to test, not a conclusion to confirm. Check it against the record independently and report
what the record says, including when it says nothing.

## Skipping a search by anticipation

Deciding up front that the tracker or the design docs will not have it. The cost of a search that
comes back empty is one search. The cost of missing a design document that exists is an answer that
is wrong and cited. Only the two permitted skip reasons apply, and "probably irrelevant" is not one.

## Flattening the hedges on the way out

The confidence language is the product, not a stylistic layer over it. Rewriting "appears to have
been" as "was" when summarising destroys the one thing that distinguishes this output from a guess.
That includes summarising for a human who seems impatient.

## Two that bite this skill's own operation

**The record is honest about its own gaps and the skill still has to be.** A repository with a thin
paper trail produces a mostly-`Unknown` report. That is a correct result, not a failed run, and it is
useful: it tells the reader the decision was never written down, which is itself a finding about how
the team works.

**An unavailable category is not a skipped one.** Reporting "tracker: no relevant results" when no
tracker resolved at all is a false negative — it implies a search happened. Say the category was
unavailable and name it as a gap.
