---
bump: none
---

No release: only eval cases change. Adds the four new-defect fanout reviewer-diversity fixtures (`stock-race`, `csv-handle-leak`, `price-cents`, `vacuous-slug-test`), each with a ground-truth file and one case per arm (L, M, M+X, L+X), planting a race on shared state, a resource leak on an error path, a caller left on an old contract and a test that cannot fail.
