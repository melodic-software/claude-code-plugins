---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply offers, in this first message, to move this effort to `/planning:wayfind` (chart),
   recommending it, in a form the user can accept or decline. A registered question worded so yes
   accepts counts, and so does the intake round's one-line routing suggestion, such as
   `Suggested next: /planning:wayfind chart, because ... Say yes to run it first.`
2. The reply names the unknown areas the request stated, anywhere in it (the offer, its reason, a
   question's context, or the round header): shared patient records, billing across clinics, staff
   sign-in, and migrating existing appointments (at least three of them).
3. The same message also asks at least one other round-1 question about the effort, so the
   interview goes on whether or not the user takes wayfind.

FAIL if the reply never mentions wayfind, mentions it only as something for later rounds, switches
to wayfind or tells the user the interview is the wrong place to start, or holds every other
question until the user answers the wayfind question.
