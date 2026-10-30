---
bump: patch
---

### Changed

- Eval case `t3-setup-interactive-release` now carries labeled samples for its three judge graders (`true-facts`, `release-no-bypass-claim` and `release-interactive`), built from the committed T3 labels: the labeled `AGENTS.md` diffs, at least five that must pass and five that must fail per grader. The three graders now accept either the conventions file or a diff of the markdown files setup wrote, and fail only when there is no such text. `true-facts` also lists the fixture's `load_accounts` helper, the `-Version` parameter of `scripts/release.ps1` and the `SlugifyTests` cases, so a judge no longer has to guess whether they exist. ([#9993](https://github.com/melodic-software/claude-code-plugins/issues/9993))
