---
bump: patch
---

### Fixed

The lookup skill's CLI reference no longer says `ctx7 skills` is still runnable or that `CONTEXT7_API_KEY` is required for `ctx7 skills generate`: the installed CLI has neither `skills` nor `generate`. The guidance never to run `ctx7 setup` or `ctx7 skills install` stays, reworded so it does not claim the second works.
