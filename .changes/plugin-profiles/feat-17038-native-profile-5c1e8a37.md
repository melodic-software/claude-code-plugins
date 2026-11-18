---
bump: minor
---

### Added

- A shipped `native` profile: Claude Code as it ships, with every plugin of the marketplaces the profiles name switched off, guardrails and the other always-on plugins included, and only the profile switcher kept on as the way back. Its preview, in a terminal, in `/plugin-profile` and in `start`, says that guardrails and the other always-on plugins are off and names them ([#17038](https://github.com/melodic-software/claude-code-plugins/issues/17038)).
- A profile key, `always_on: false`, makes a profile's own lists the whole set, without `always-on.yaml`'s; such a profile may also exclude an always-on member. Shipped and user-level files can set it; a repository file that sets it is ignored and the preview, `check` and `save` say so ([#17038](https://github.com/melodic-software/claude-code-plugins/issues/17038)).
