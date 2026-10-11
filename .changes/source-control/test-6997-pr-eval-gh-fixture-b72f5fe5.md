---
bump: patch
---

### Added

- **An offline gh fixture for the `pull-request` ready eval cases.** `evals/fixtures/gh-forge/` gives a scaffolded repository a bare local `origin` and a `gh` stand-in that serves one open draft pull request (view, list, diff, ready) and refuses everything else, so no run reaches GitHub. A case cannot set `PATH`, so the scaffold puts the stand-in on it through `~/.zshenv` in the run's temporary home, which zsh reads for every command; the fixture therefore reaches the stand-in only when the operator's shell is zsh. `pull-request-ready-hands-pr-to-explain-change` and `pull-request-ready-merges-base-never-rebases` now use it, so a correct ready run gets past the pull request lookup to the base merge, the flip and the explain-change hand-off. The skill body is unchanged.
