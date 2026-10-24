---
bump: none
---

No plugin file ships changed: the root `.lefthook/` remote scripts, which consumers fetch from `main`, now run only from lefthook's `info/lefthook-remotes/` cache (on Windows too), and the lefthook-remote test checks it.
