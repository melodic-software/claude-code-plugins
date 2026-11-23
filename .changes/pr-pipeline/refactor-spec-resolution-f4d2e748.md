---
bump: none
---

No behavior change: which spec source wins for a linked issue (written, split child, own-agent, briefed, recurring, upstream drift, main-red incident) moves out of `resolve-pr.mjs` into `.github/scripts/pr-verify/spec-source.mjs`, a pure function with a table test, which joins the hold floor beside `resolve-pr.mjs`.
