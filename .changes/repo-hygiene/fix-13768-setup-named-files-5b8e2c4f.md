---
bump: patch
---

### Fixed

- name the files setup reads instead of searching the plugin directory

  setup reads the clean skill, clean-common.sh, exec-bash.mjs and the README
  with the Read tool by their plugin-root paths, never globs, greps or lists the
  plugin directory, and runs each probe as its own Bash call. It no longer looks
  for a hooks manifest the plugin does not ship.
