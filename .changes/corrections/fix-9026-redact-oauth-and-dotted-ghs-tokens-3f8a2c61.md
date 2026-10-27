---
bump: patch
---

### Fixed

- **The findings buffer redacts bare `sk-ant-oat01-` tokens and dotted `ghs_` tokens whole ([#9026](https://github.com/melodic-software/claude-code-plugins/issues/9026)).** Its copy of `redact.py` now runs two of its own rules before the vendored gitleaks rules. Before this, a bare `sk-ant-oat01-` value reached the adapter unredacted, and the vendored `github-app-token` rule replaced only the first 36 characters of a stateless `ghs_` token containing a dot, so the rest of the token stayed in the row.
