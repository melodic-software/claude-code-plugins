---
bump: none
---

Fix four eval cases from the #19507 round-3 runs: the reassess verdict graders accept "The verdict is continue", the continue case ends on the head branch, the hands-pr case skips verify and has its own skill-fired grader, and the gh-forge fixture serves a reply to a review thread that names a real finding. No shipped skill text changed.
