# locate

Find the glossary and glossary index that cover a scope. Read-only. `lookup`, `seed`, `curate` and
`audit` all start here.

## Input

A scope: files, a directory or a domain area from the request or the caller's task. With none, the
repository.

## Steps

1. **Declared convention.** Read the consuming project's `AGENTS.md`, `CLAUDE.md`, `.claude/rules`
   and declared documentation conventions for a stated glossary path. A declared path wins.
2. **Search the repository.** Glob the tracked tree, case-insensitively, for domain-vocabulary files:
   the two resolved setting names below, `glossary.md`, `*-glossary.md`, `ubiquitous-language.md`,
   and the same names under any `docs/` folder. Skip `node_modules`, build output, vendored code,
   and glossaries that are plainly not the project's domain language (a tool's own reference
   glossary under a plugin or package's reference folder). A walk up from the scope alone is not
   enough: `docs/glossary.md` beside the code is a sibling, never an ancestor.
3. **Pick per scope.** With one candidate, it covers the repository. With several, use the glossary
   index first, then the candidate nearest the scope (same module root, then its `docs/`, then the
   repository root and root `docs/`). When two remain plausible for a scope, report both and say
   which question would settle it; never merge them.
4. **Resolve the setting names** (only needed when step 2 searched by them, or nothing was found and
   a name must be proposed):
   follow SKILL.md "Settings", which carries the values the harness fills in.

## Output

One line per scope, then the index when there is one:

```text
Glossary: docs/glossary.md (found by search)
Glossary index: none
```

With nothing found: `Glossary: none` plus the name the contract's ladder would propose and the
setting layer it came from. `locate` never creates a file.
