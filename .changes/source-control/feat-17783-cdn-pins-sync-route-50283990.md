---
bump: patch
---

### Fixed

- babysit-prs: the pr-merge lane's Dependabot gate takes the lanes App's CDN pins sync commit on a reviewed pull request (`cdn_sync_refusal`): a single-parent `[dependabot skip]` commit GitHub signed for the lanes App whose files are only the base `lib/cdn-pins/pins.json` and its `targets[].path`, each modified in place as a regular non-executable file on both sides. Any other file, an added, deleted or renamed file, a mode change, another author, a second parent or an unreadable base registry still refuses.
