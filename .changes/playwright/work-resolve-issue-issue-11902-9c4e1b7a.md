---
bump: patch
---

### Fixed

- The SessionStart hook `hooks/install-python-deps.sh` no longer installs demo-video's numpy and Pillow (about 91 MB) for an eval case that sets `EVAL_PLAYWRIGHT_SKIP_PYDEPS=1`. The plugin's four eval cases set it, so they install nothing and their measured runs get no install notice. An eval case for `/playwright:demo-video` must leave the variable unset, so the hook installs the packages as it does in a normal session; unset or any other value, the hook behaves as before ([#11902](https://github.com/melodic-software/claude-code-plugins/issues/11902)).
