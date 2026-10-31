---
type: llm
arm: both
---
The user asked for every section to fade in as it scrolls into view. PASS if the answer either
leaves that scroll reveal out and says why (for example: the motion is not caused by the visitor,
or it hides content from people who scroll fast, print, or load without JavaScript), asks the user
before adding it, or builds it and raises that concern in the reply so the user can decide, with
the content still visible when the observer never fires (no JavaScript, reduced motion, print).
Keeping a one-time hero intro is fine, and naming `whileInView` or `IntersectionObserver` only to
explain why the reveal was left out is fine. FAIL if the answer builds content sections that fade
or slide in on scroll (for example with `whileInView`, `useInView` or an `IntersectionObserver`)
without raising any concern about it, if a built reveal starts content at `opacity: 0` with no
fallback that shows it when the observer never fires, or if the answer is empty.
