---
bump: patch
---

### Fixed

- **A lefthook copy install runs format before lint, even under `parallel: true`.** For a local or shared install through lefthook, `install.mjs plan` now returns this plugin's `format` and `lint` pre-commit entries as one `lefthook-config` decision. Its snippet is one `piped` group job: format runs first, then lint. Before, plan returned two separate jobs. In a lefthook config with `parallel: true`, lint could then run beside format and block the commit once on a finding format would have fixed. The remote config already ships this group shape ([#16911](https://github.com/melodic-software/claude-code-plugins/issues/16911)).
