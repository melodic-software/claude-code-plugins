# Target scope adopters

The skills that accept the [target-scope contract](README.md)'s target forms. This table is not
copied into any plugin: add a row here, and register the plugin's own copy of `README.md` in
`scripts/shared-copies.txt`.

| Skill | Status |
|---|---|
| `/architecture:improve` (deepening and conventions lenses) | Through `improvement-steps.md` "Scope and fan-out" and its plugin-shipped copy |
| `/bugs:scan` | Points here through its plugin-shipped copy; lane cursor, reports and `--track` filing stay per repository |
| `/coupling:reduce` | Points here through its plugin-shipped copy; measures cross-repository copies |
| `/code-metrics:audit`, `audit-coverage`, `audit-duplication`, `audit-suppressions` | Through `reference/several-repositories.md` and the plugin-shipped copy; one report per repository, and only `--findings` writes |
| `/docs-naming:audit-file-names` | Points here through its plugin-shipped copy; one plan per repository, audited in that repository's worktree |
| `/docs-naming:realign-file-names` | Points here through its plugin-shipped copy; applies one repository's plan at a time |
| `/improvement:find` | Points here through its plugin-shipped copy; ranks all repositories' candidates on one scale |
| `/improvement:improve` | Points here through its plugin-shipped copy; ships one PR per repository |
