---
bump: patch
---

### Changed

- The setup skill's reconfiguration guidance keeps its decisions (reconfigure through the native configure flow, never uninstall to reconfigure, recheck in a fresh session) and now points at the plugin-reconfiguration convention's "The routes" and "Caveats" sections and the plugin CLI reference's `plugin configure` section instead of restating the headless command, its version floor and failure signals, and drops any claim that option values are fixed at session start or skill load, which the docs do not state.
- Eval cases that graded the removed reconfiguration wording now grade the decisions: the native configure route, the option key and value, a pointer at the convention, no uninstall, and the fresh-session recheck.
- The plugin now ships a generated copy of the plugin-reconfiguration convention at `reference/plugin-reconfiguration.md`, and its skills link that copy by relative path, so an agent without network access can read the routes and caveats the skills point at.
