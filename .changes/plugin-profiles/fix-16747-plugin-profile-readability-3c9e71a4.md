---
bump: minor
---

### Added

- `/plugin-profile` picks from one pane listing every profile and **No profile**, with a Cancel button: a Select, or a button per entry on mobile, which may not draw a Select; where no pane can be placed it falls back to the paged question dialog ([#16747](https://github.com/melodic-software/claude-code-plugins/issues/16747)).
- `/plugin-profile` offers **No profile**, which clears this folder's profile behind the same preview and confirm as a switch, then reloads at the next turn's end; a folder with no profile says so and how to drop an earlier profile's plugins still loaded ([#16747](https://github.com/melodic-software/claude-code-plugins/issues/16747)).

### Fixed

- `/plugin-profile` shows the profile list and the preview one line each, and counts the plugins left alone instead of naming them, so nothing renders as one cut-off paragraph; the confirm no longer names the running session among the other sessions in the folder; its closing line carries no doubled `plugin-profiles:` prefix and names the plugins left loaded only when the switch turned some off; and after Apply it says to send any message or run `/reload-plugins` to load the change ([#16747](https://github.com/melodic-software/claude-code-plugins/issues/16747)).
