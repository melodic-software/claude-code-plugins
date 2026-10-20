---
bump: none
---

Docstring and tests only: pr-merge's open-findings count already closes a resolved thread, whoever resolved it, on a clean whole review of the current head in the thread's lane, and never on a clean incremental review; the tests now pin both, including a resolved security thread staying open after a clean incremental review. No shipped behavior changes.
