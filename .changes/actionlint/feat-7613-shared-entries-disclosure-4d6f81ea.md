---
bump: patch
---

### Added

- The git-hook installer's shared plan (`lib/git-hooks/install.mjs plan --scope shared`, plain hooks, `core.hooksPath` not yet `.githooks`) returns a `shared-entries` decision before `hooks-path`, listing what setting `core.hooksPath` would also run that this plugin did not install: `<event>.d/` markers other than its own, any `.githooks/*.pre-checks` hook, any other hook file there that is not the dispatcher, and every tracked file under `.githooks/local/` ([#7613](https://github.com/melodic-software/claude-code-plugins/issues/7613)). Setup shows the list and sets `core.hooksPath` only on the user's yes. With none present the plan is unchanged.
