## Problem

Each review lane posts its own findings comment, so one pull request can carry three comments that
repeat the same finding.

## Requested behavior

The review lanes share one set of findings per pull request. Two ways I can see, and I have not
chosen:

- a new job, after every lane, that merges the lanes' findings into one comment; or
- each lane edits one shared comment in place, adding its findings to what is there.

## Done when

- [ ] A pull request carries one findings comment from the review lanes.
