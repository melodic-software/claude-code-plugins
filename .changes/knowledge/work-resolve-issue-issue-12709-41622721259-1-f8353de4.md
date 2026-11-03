---
bump: minor
---

### Changed

- `/knowledge:absorb-upstream` reads a repository through the GitHub REST API at the pin (the default branch head's commit) and no longer clones it, so no file of a repository source is written under a working tree or a temp directory. A symbolic link in the tree is reported as not read. A repository URL that does not read `public` stops with the local-checkout instruction, whatever the destination. A page is fetched into a new directory under `${CLAUDE_PLUGIN_DATA}` (#12709).

### Removed

- `vendor/repo-analysis/clone-cli.js` and its tests: nothing calls it now. `clone.js` stays for course-digest and video-digest (#12709).
