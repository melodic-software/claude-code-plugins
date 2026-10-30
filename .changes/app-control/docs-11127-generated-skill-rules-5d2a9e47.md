---
bump: patch
---

### Changed

- **The control-skill contract states five more rules for a generated control skill** ([#11127](https://github.com/melodic-software/claude-code-plugins/issues/11127)). A feature is a user's goal and a sub-feature is a state or branch inside it. A `not driven: <reason>` entry point names what would make it drivable. UI that differs by tenant or configuration is a named precondition in `## Drive` or a step whose selector matches every variant. A project's auth bootstrap, when it has one, runs the mapped sign-in steps from `shared/` or from the integrated app that owns sign-in, so sign-in selectors live in one place. A feature that signs out runs in a throwaway browser session, never in the saved one, and signs in there within the Sign-in floor's one attempt per account.
