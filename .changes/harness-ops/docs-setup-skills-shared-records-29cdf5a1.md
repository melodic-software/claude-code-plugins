---
bump: patch
---

### Changed

- The setup skill's reconfiguration guidance keeps its decisions (reconfigure through the native configure flow, never uninstall to reconfigure, recheck in a fresh session) and now points at the plugin-reconfiguration convention's "The routes" and "Caveats" sections and the plugin CLI reference's `plugin configure` section instead of restating the headless command, its version floor and failure signals, and drops any claim that option values are fixed at session start or skill load, which the docs do not state.
