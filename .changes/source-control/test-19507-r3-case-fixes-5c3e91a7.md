---
bump: none
---

Fix four eval cases from the #19507 round-3 runs: the seven reassess graders that decide the reply's verdict are now llm judges, with labeled calibration samples, because a pattern cannot tell whether a statement is the reply's final verdict, the continue case ends on the head branch, the hands-pr case skips verify and has its own skill-fired grader, and the gh-forge fixture serves a reply to a review thread that names a real finding, with the fields and types of a captured GitHub reply. No shipped skill text changed.
