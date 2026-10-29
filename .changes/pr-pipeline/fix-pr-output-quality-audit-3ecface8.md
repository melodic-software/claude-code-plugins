---
bump: patch
---

### Fixed

- The pr-verify fail note no longer scrolls sideways. Each line of the verifier's quoted summary
  and notes is wrapped at a space within 100 columns, continuations indented two spaces, with a
  word longer than that (a URL or path) kept whole; a quote over 20 lines folds into a
  `<details>` block. The text stays in its `text` fence, so a mention, reference, link or HTML in
  it stays inert.

### Added

- A "Write identities" section lists which workflows write as `GITHUB_TOKEN`, the lanes App, the
  release App or the owner token, and why each split exists.
