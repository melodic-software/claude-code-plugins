---
bump: minor
---

### Changed

- `control-claude-code` screenshots and videos never capture the live screen: the driver masks the signed-in account, organization, login method, session id, working directory, home paths, cost, token counts and usage-limit lines (the hub's new `## Mask`), redraws the masked screen in a second terminal and captures that, and writes the text it drew beside each capture as `<path>.txt`. A frame that does not redraw exactly fails the capture with nothing written. `cli/account.mjs` prints the signed-in email and organization for drive's mask post-check.
- The driver's new `plugins <changed files>` verb names the plugin each changed file sits in, and the hub launches one session per changed plugin in turn. `config/defaults.json` sets `maxEntryPoints: 6`, the entry points a run drives; `plugins` lists at most that many plugins and names the rest blocked.
- The index's `sources` now cover hook scripts, skill `reference/` and `scripts/`, and agents.
