# audit-instructions: several repositories

With no target form, the audit covers the project the session runs in, as every phase in
[`../SKILL.md`](../SKILL.md) describes. The target forms (`--repo`, `--repos-from`, `--owner`,
`--fleet`, `--skip`, or the same request in words) sit beside the surface scope, which still
filters findings in each repository. They select several repositories, which resolve, count, fan
out and merge as the plugin's copy of the target-scope contract,
[`<plugin-root>/reference/target-scope.md`](../../../reference/target-scope.md), says in "Target
forms", "Resolving repositories", "Fan-out" and "Merging findings". What differs here:

- **Each repository's pass runs Phases A to D with that clone's root as the project**, walking the
  project paths under `<root>` and handing the pre-scans files under it. The pass reads the clone's
  working tree, not `origin/HEAD`, because the pre-scans take file paths and `CLAUDE.local.md` is
  untracked.
- **User-scope surfaces are inventoried in every pass**, since I15 pairs them with each project's
  surfaces. The same user-scope finding from several passes merges into one row.
- **Run state stays per repository**: pass `--root <clone root>` to `run-state.sh paths`,
  `lib/state-key.sh` and `persist-report.sh`, so each repository gets its own `<state-key>`, run
  directory, lease and `last-audit.md`, and `--resume` resumes each one under its own key.
- **One ~20-dispatch confirmation covers the whole run**, counted over every repository's lanes and
  verifiers, so a several-repository run asks once, or with `--unattended` discloses once.
- **`--persist-findings` writes only the session's own repository's file**, since the file lands in
  a working tree and another clone's main checkout is never written. Every other repository's
  findings stay in the report, named as not persisted.
