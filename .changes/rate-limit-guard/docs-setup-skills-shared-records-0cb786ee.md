---
bump: patch
---

### Changed

- The setup skill's reconfiguration guidance keeps its decisions (reconfigure through the native configure flow, never uninstall to reconfigure, recheck in a fresh session) and now points at the plugin-reconfiguration convention's "The routes" and "Caveats" sections and the plugin CLI reference's `plugin configure` section instead of restating the headless command, its version floor and failure signals, and drops any claim that option values are fixed at session start or skill load, which the docs do not state.
- The setup skill's pre-computed context keeps its fallback for a row showing the `disableSkillShellExecution` placeholder and adds a pointer record to the skills docs' "Inject dynamic context" section, where that placeholder text is documented.
- The setup check's fresh-session rule for observing a changed option no longer gives "injected when this skill loads" as its reason and points at the plugins manifest reference's "Reference a saved value" section instead. In rate-limit-guard it also drops the unpointed claims about when the module and the StopFailure hook read a changed value.
- The plugin now ships a generated copy of the plugin-reconfiguration convention at `reference/plugin-reconfiguration.md`, and its skills link that copy by relative path, so an agent without network access can read the routes and caveats the skills point at.
