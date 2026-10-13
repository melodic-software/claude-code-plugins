---
type: llm
arm: both
---
PASS only if the answer's animation includes, in the same answer, a reduced-motion variant in which
the panel does not slide (a short opacity change may remain), whatever mechanism expresses it. FAIL
if there is no reduced-motion handling, if it is only suggested as a follow-up, or if the panel
still slides under reduced motion.

Examples:

- PASS: the slide sits inside a no-preference reduced-motion query and the panel otherwise just
  appears or fades.
- FAIL: "You may also want to respect reduced motion."
