---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply asks, in this first message, whether to move this effort to `/planning:wayfind`
   (chart), recommending it, in a form the user can accept or decline.
2. The question or its context names the unknown areas the request stated: shared patient records,
   billing across clinics, staff sign-in, and migrating existing appointments (at least three of
   them).
3. The same message also asks at least one other round-1 question about the effort, so the
   interview goes on whether or not the user takes wayfind.

FAIL if the reply never mentions wayfind, mentions it only as something for later rounds, switches
to wayfind or tells the user the interview is the wrong place to start, or holds every other
question until the user answers the wayfind question.
