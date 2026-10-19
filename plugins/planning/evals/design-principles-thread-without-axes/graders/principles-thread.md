---
type: llm
focus:
  source: file
  path: .work/loyalty-points/design/design-threads.md
---

The file is the design-threads record for a loyalty-points calculation module.

PASS if it holds a thread or section about principles (headed or labeled Principles, or plainly a
record of which design principles shaped this design) that both:

1. names at least one specific design principle or default that shaped the module (for example
   single responsibility, information hiding, deep modules, YAGNI, pure functions, DRY of
   knowledge, or a consumer standard that overrides a bundled default), and
2. records how the generalize-now-or-wait question was settled for this module: whether to build
   for further variants or rule sets now or wait until a second one exists, with the outcome (for
   example "wait: the Brief's Intent line expects no second variant") or the question recorded as
   blocked or deferred for the user.

FAIL if the file is empty or missing, has no principles thread, names principles only in passing
inside another thread without recording the generalize-now-or-wait outcome, or records principles
without any generalize-now-or-wait outcome.
