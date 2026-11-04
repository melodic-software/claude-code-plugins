---
bump: patch
---

### Changed

- The music and sfx eval suites moved from `skills/<skill>/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`: the six legacy cases became six cases, `mu-*` for music and `sx-*` for sfx, that grade the rendered WAV, the success line each script prints, and which skill a near-miss prompt loads ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Both `evals.json` files are deleted.
