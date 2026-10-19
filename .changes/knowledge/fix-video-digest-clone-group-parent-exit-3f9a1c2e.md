---
bump: patch
---

### Fixed

- `/knowledge:video-digest` no longer leaves a harvested-repo clone running when its parent process dies. The parent tracks each live clone process group and kills it on exit, SIGINT, SIGTERM and SIGHUP, then re-raises the signal so it still dies the conventional way. SIGKILL of the parent cannot be caught, and Windows behavior is unchanged.
