# Report keying — where Phase D persists, and why the key matters here

Phase D persists its report to
`${CLAUDE_PLUGIN_DATA}/audit-instructions/<state-key>/last-audit.md`.

The keying scheme, its retention shape, and the overwrite rules are the marketplace's
`plugin-data-report-keying` convention (`docs/conventions/plugin-data-report-keying/README.md`).
This file records only what an `audit-instructions` run does with it.

## Deriving the key

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"
```

It prints `<repo-identity>/<worktree-discriminator>`, implemented once in the shared
`lib/state-key.sh` that `audit-prompting-postures` also uses. Run it and use the result.

Do **not** express the path as a condition over `${CLAUDE_PROJECT_DIR}` "when set": that
placeholder is substituted inline before the skill body reaches you, so the literal token is never
visible and the condition is not yours to evaluate.

## Why the key is load-bearing in this skill specifically

`${CLAUDE_PLUGIN_DATA}` resolves to `~/.claude/plugins/data/{id}/`, keyed to the plugin identifier
and nothing else ([plugins reference](https://code.claude.com/docs/en/plugins-reference),
§ Persistent data directory). Under a fixed filename every run from every project on the machine
overwrites the last — and Phase D's cost line would then compute its **per-surface token delta
against a prior report belonging to a different project's surface set**, printing a number rather
than declining.

The lost artifact is the smaller half of that; a silently wrong figure in the report header is the
larger one.

## Two absent-prior cases, and they are not the same

- **No report at the derived key** → say so and omit the delta ("first run for this project; no
  prior catalog version to compare"). Never reach for another file to compare against.
- **A legacy unkeyed `audit-instructions/last-audit.md`** left by an earlier version has no project
  segment and is therefore unattributable → name its path to the operator as a leftover, and
  compute no delta from it.

Both are the keying convention's own rules ("absent prior"), applied here rather than restated.
