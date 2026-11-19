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
| `/docs-hygiene:audit-derivability` | Through docs-hygiene's `context/clean-tree-fallback.md` "Several repositories" and its plugin-shipped copy |
| `/docs-hygiene:audit-encapsulation` | Same; `fix` and `file-issues` act in the hit's own repository |
| `/docs-hygiene:audit-noise` | Same; one `--persist-findings` file per repository |
| `/docs-hygiene:audit-progressive-disclosure` | Same |
| `/docs-hygiene:compress` | Same; settings read per repository |
| `/docs-hygiene:extract-ssot` | Same; a fact repeated across repositories stays in its owner and the others point at it |
| `/docs-hygiene:rename-references` | Same; one rename pair swept in each repository |
| `/docs-naming:audit-file-names` | Points here through its plugin-shipped copy; one plan per repository, audited in that repository's worktree |
| `/docs-naming:realign-file-names` | Points here through its plugin-shipped copy; applies one repository's plan at a time |
| `/improvement:find` | Points here through its plugin-shipped copy; ranks all repositories' candidates on one scale |
| `/improvement:improve` | Points here through its plugin-shipped copy; ships one PR per repository |
| `/instruction-placement:audit` | Points here through its plugin-shipped copy; one findings artifact per repository, plus a rule several repositories repeat |
| `/instruction-placement:delta` | Points here through its plugin-shipped copy; one baseline and findings artifact per repository |
| `/instruction-placement:check` | Points here through its plugin-shipped copy; one gate verdict per repository |
| `/instruction-placement:realign` | Points here through its plugin-shipped copy; applies one repository's findings at a time |
| `/repo-hygiene:clean` (batch forms) | Source of the flags; points here through its plugin-shipped copy; `--repo` and `--repos-from` take local paths only and, alone, keep every clone they name |
