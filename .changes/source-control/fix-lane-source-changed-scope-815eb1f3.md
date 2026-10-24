---
bump: patch
---

### Changed

- Babysit review evidence now unbinds the review lanes (`lane-source-changed`) only for a change to what a pull request's checkout feeds its own review: the two review caller workflows, `plugins/review/`, a `.claude/` directory, `.mcp.json`, `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `REVIEW.md` or `.gitattributes` at any depth, `docs/standards/`, the instruction exception register and untrusted-content conventions, and `.claude-lane/`. Other files under `.github/` no longer unbind them: the callers run their local actions from a checkout of main, and the reusable workflow runs its composites from its own repository.
