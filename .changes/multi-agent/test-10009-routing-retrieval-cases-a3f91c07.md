---
bump: patch
---

### Added

- **Routing eval: retrieval cases.** Six `rt-*` cases under `evals/routing/retrieval/` ask codebase-retrieval questions (locate code, trace callers, where something happens) about a pinned snapshot of the `multi-agent` and `evals` plugins, each graded by deterministic regex graders with must-pass and must-fail samples. Their README gives the arm configuration (model and effort level) for each setup the paired routing eval compares ([#10009](https://github.com/melodic-software/claude-code-plugins/issues/10009)).
