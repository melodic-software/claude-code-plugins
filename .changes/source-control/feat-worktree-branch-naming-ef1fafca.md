---
bump: minor
---

### Added

- `worktree_branch_naming`, a team setting in `docs/conventions/source-control.yaml` that sets how
  `worktree-create.sh`, and so the `WorktreeCreate` hook, names a new worktree's branch. `verbatim`,
  the default, keeps today's behavior: the branch is the worktree name. `conventional-commits`
  derives `<type>/<description>`: a first segment that is a Conventional Commits type, an alias of
  one or a `worktree_branch_extra_prefixes` entry stays the type, and any other name goes under
  `worktree_branch_default_type` (default `chore`), so an isolated Agent spawn's `agent-<id>`
  becomes `chore/agent-<id>`. The derived branch is made ref-safe and checked against git's branch
  grammar; the directory slug still comes from the name. An unknown value, an untracked file or a
  YAML the parser rejects keeps the name verbatim with a note on stderr, so naming never fails a
  worktree creation.
