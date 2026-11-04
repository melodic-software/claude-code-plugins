---
bump: patch
---

### Fixed

- Shared `fetch-docs.sh` synced where this plugin carries it ([#12945](https://github.com/melodic-software/claude-code-plugins/issues/12945)): with `--profile generic`, an x.com or twitter.com page that is X's logged-out shell (`redirect_after_login` links and no article text) is now `unread` with reason `login-wall` instead of `read`, whether fetched or served from the cache or a fixture, and is never cached; no other change to this plugin.
