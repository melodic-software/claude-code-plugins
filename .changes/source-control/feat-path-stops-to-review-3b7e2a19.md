---
bump: minor
---

### Changed

- The review-thread tool (`feedback-thread.sh`) of `comments --ci` checks only that a path is plain and in normal form; `reference/comments-ci.md` drops the thread-scope rules, and says the push job withholds a workflow, settings, agent instruction, `.claude/`, MCP or LSP config or `.gitattributes` change as a proposed diff. `ci --ci` (`reference/ci-ci.md`) writes a workflow fix into the working tree like any other fix instead of escalating `protected-path`. The `resolve-conflicts` lane note names a needed workflow change in its reply instead of escalating the path, and leaves agent instruction files, `.claude/`, MCP and LSP config and `.gitattributes` to the runner.
