---
bump: patch
---

### Changed

- `pr-unblock-dispatch.yml` also runs half-hourly, at minutes 9 and 39, five minutes after each `maintenance-reconcile-lost-runs` tick. A lanes App pull request whose reconciler re-run failed now gets `fix-ci` within one interval instead of waiting for the next push to `main`, and a conflicting or Markdown-changing pull request is picked up the same way. A tick runs the same listings as a push run, and with nothing to dispatch it reads nothing per pull request past them. The gate and the token broker already accept a dispatcher run started by a schedule. A re-run of a scheduled run fails at the trigger check, which handles no `schedule` event; the next tick replaces it.
