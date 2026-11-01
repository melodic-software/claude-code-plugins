---
bump: patch
---

### Fixed

- The SessionStart hook `hooks/install-python-deps.sh` no longer installs demo-video's numpy and Pillow (about 91 MB) when the session runs under `claude plugin eval`. It skips the install when the plugin data directory is inside a `claude-eval-*` sandbox, so a trigger-only eval case installs nothing and its measured run gets no install notice. A demo-video eval case gets `pydeps.py run`'s repair line instead ([#11902](https://github.com/melodic-software/claude-code-plugins/issues/11902)).
