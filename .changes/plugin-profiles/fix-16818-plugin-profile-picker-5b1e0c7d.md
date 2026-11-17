---
bump: patch
---

### Fixed

- `/plugin-profile` answers as soon as the picker pane opens and runs the pick from the pane, so it no longer overruns its hook's 10-second budget and every outcome line prints ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).
- The picker pane draws every profile and **No profile** as a row at once instead of a closed drop-down; a row's whole description shows under the pointer, and the focused row's under the list ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).
- The preview names the plugins a switch turns off once: "Left on until the next apply" counts them, and so do the closing and in-force lines ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).
- `status` and `clear` find a profile another copy of the plugin applied, such as a `--plugin-dir` copy whose record sits in `plugin-profiles-inline`, instead of saying nothing is recorded ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).
