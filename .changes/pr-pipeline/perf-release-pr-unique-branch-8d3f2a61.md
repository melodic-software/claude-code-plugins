---
bump: patch
---

### Changed

- Each release pull request gets its own branch, `release/plugins-<run id>` of the `release-publish-plugins` run that opens it, and a rebuild reuses the open one's branch. A branch-scoped run listing for a release pull request then holds only that release's runs instead of every earlier release's. The release gates and `changelog_fragments::is_release_pr` recognize `^release/plugins(-[0-9]+)?$`, so a release still open on the bare `release/plugins` keeps working. The convention's ruleset note now names both release branch forms.
