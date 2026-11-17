## Problem

The work-items plugin's eval suite runs only when someone starts it, so a regression can sit for
weeks.

## Requested behavior

A scheduled workflow runs the suite once a week on the lanes' prepaid API key and posts the score
to the lane telemetry issue.

## Done when

- [ ] A workflow runs the work-items eval suite every Monday.
- [ ] Each run posts its score to the lane telemetry issue.
