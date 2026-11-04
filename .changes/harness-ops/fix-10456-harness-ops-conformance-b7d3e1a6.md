---
bump: patch
---

### Fixed

- `lane-launcher.test.sh`: the no-claude PATH reaches `jq` through a wrapper instead of adding jq's
  directory, so the cases hold on a host that keeps `claude` beside `jq`.
- `session-event-log.test.sh`: every run clears an inherited `TRACEPARENT`, so the mod-environment
  parity cases hold inside a traced session.
- `/harness-ops:audit-performance` eval: the disabled-on-disk case expects `/reload-plugins` or a
  restart, as the stale-session advisory now says.
- `/harness-ops:audit-performance`: the stale-session advisory says permissions and hooks edits
  reach a running session, and claims a pending change only for a plugin enable or disable.
- `audit_skill_visibility.py`: the `enabledPlugins` merge record names the `--add-dir` source it
  leaves out.
- `/harness-ops:plugins` gotchas: the `marketplace remove` record keeps the bundle as the basis for
  the settings cleanup the docs do not state.
