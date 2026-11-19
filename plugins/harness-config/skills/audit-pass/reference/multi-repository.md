# audit-pass: several repositories

With no target form, the pass audits the active project root, as every phase in
[`../SKILL.md`](../SKILL.md) describes. The target forms (`--repo`, `--repos-from`, `--owner`,
`--fleet`, `--skip`, or the same request in words) select several repositories, which resolve,
count, fan out and merge as the plugin's copy of the target-scope contract,
[`<plugin-root>/reference/target-scope.md`](../../../reference/target-scope.md), says in "Target
forms", "Resolving repositories", "Fan-out" and "Merging findings". What differs here:

- **Each repository gets the whole pass, Phase 0 to Phase 6, with that clone's root as `target`.**
  The pass reads the clone's working tree, not `origin/HEAD`, because the scan baseline is the
  target's HEAD plus a digest of the files on disk, and the delegates read what is on disk.
- **A delegate that accepts a target is given that repository**:
  `/harness-config:audit-instructions` and `/harness-memory:audit` both take `--repo <clone root>`.
  A delegate that takes no target (`/harness-config:audit`, `audit-permission-state`,
  `audit-permission-grants`, `audit-prompting-postures`) reads the active project only. It runs
  only in the active project's pass, when that project is selected, and every other repository's
  pass lists its lane in `skipped` with the reason `delegate takes no target`. Running it there
  would attribute the active project's findings to the wrong repository, as
  [arguments.md](arguments.md) explains. The retirements sweep takes `--root`, so it runs in every pass
  with `--root <clone root>`, and the same leftover in several repositories is one row listing
  each.
- **User and managed scopes are inventoried in every pass**, since conflicts with the project
  scope depend on the project. The same user-scope or managed-scope finding from several passes
  merges into one row.
- **Run state and the lock are per repository**: run `run-state.sh paths` with
  `--root <clone root>`, so each repository gets its own `<state-key>`, run directory, lease, lock
  and report. `--resume` resumes each repository's latest run under its own key.
- **`--fix` stays per repository**: Phase 5 runs in the main session, one repository at a time,
  since every fix waits for confirmation. In the active project it applies as a single-repository
  run does. In any other repository, edits go into one worktree created at that clone's HEAD and
  one pull request, as the contract's "Writes stay per repository" says, never into the clone's
  main checkout. The lock stays on the clone root's state key, and Phase 5's third capture is
  taken in that worktree and compared, by repository-relative path, with the clone's audit
  endpoint.
