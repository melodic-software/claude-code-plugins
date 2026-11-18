---
bump: minor
---

### Added

- A shipped `native` profile: Claude Code as it ships, with every plugin of the marketplaces it and `always-on` name switched off, guardrails and the other always-on plugins included, and only the profile switcher kept on as the way back. Its preview, in a terminal, in `/plugin-profile`, in `start` and in `launch`, names the always-on plugins it switches off, says guardrails is among them only when it is, and names any always-on plugin that stays on with why: the profile switches it on, the repository's settings enable it, or managed or folder settings pin it ([#17038](https://github.com/melodic-software/claude-code-plugins/issues/17038)).
- A profile key, `always_on: false`, makes a profile's own lists the whole set, without `always-on.yaml`'s; such a profile may also exclude an always-on member. Its own `plugins` list is the whole set: an always-on plugin from a marketplace only `always-on` names is switched off too. Shipped and user-level files can set it; a repository file that sets it is ignored and the preview, `check` and `save` say so ([#17038](https://github.com/melodic-software/claude-code-plugins/issues/17038)).
