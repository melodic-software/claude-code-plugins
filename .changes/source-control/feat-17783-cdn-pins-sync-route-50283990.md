---
bump: patch
---

babysit-prs: the pr-merge lane's Dependabot gate now takes the lanes App's CDN pins sync commit on a reviewed pull request (`cdn_sync_refusal`): a single-parent `[dependabot skip]` commit GitHub signed for the lanes App that only modifies, in place, the base `lib/cdn-pins/pins.json` and its `targets[].path` files, each a regular non-executable file on both sides. Any other file, an added, deleted or renamed file, a mode change, another author, a second parent or an unreadable base registry still refuses. The hold-floor pins count `.github/scripts/apply-patch/cdn-paths.mjs` as an enforcement row.
