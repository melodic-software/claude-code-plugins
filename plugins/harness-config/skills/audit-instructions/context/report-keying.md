# Report keying: where Phase D persists, and why the key matters here

Phase D persists its report to
`${CLAUDE_PLUGIN_DATA}/audit-instructions/<state-key>/last-audit.md`.

The keying scheme, its retention shape, and the overwrite rules are the marketplace's
`plugin-data-report-keying` convention (`docs/conventions/plugin-data-report-keying/README.md`).
This file records only what an `audit-instructions` run does with it.

## Deriving the key

Run the `state-key.sh` command in `SKILL.md`'s Phase D, whose path is already resolved there. It
prints `<repo-identity>/<worktree-discriminator>`, implemented once in the shared `lib/state-key.sh`
that `audit-prompting-postures` also uses. Use the result.

Do **not** express the path as a condition over `${CLAUDE_PROJECT_DIR}` "when set": in `SKILL.md` the placeholder is substituted before the body reaches you, and in this
file, read with the Read tool, it arrives as literal text, so in neither place is the condition
yours to evaluate. Derive the key from the command.

- **Pointer**: when deciding how a skill placeholder reaches the body, fetch
  [skills: available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: that section changes where or when `${CLAUDE_PROJECT_DIR}` is substituted.

## Why the key matters in this skill specifically

`${CLAUDE_PLUGIN_DATA}` is one directory per plugin, shared by every project on the machine. Under a
fixed filename every run from every project on the machine
overwrites the last, and Phase D's cost line would then compute its **per-surface token delta
against a prior report belonging to a different project's surface set**, printing a number rather
than declining.

The lost artifact is the smaller half of that; a silently wrong figure in the report header is the
larger one.

- **Pointer**: when deciding what `${CLAUDE_PLUGIN_DATA}` is keyed to, fetch
  [plugin manifest reference: environment variables](https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: that section keys the data directory to anything beyond the plugin, such as
  the project.

## Two absent-prior cases, and they are not the same

- **No report at the derived key** → say so and omit the delta ("first run for this project; no
  prior catalog version to compare"). Never reach for another file to compare against.
- **A legacy unkeyed `audit-instructions/last-audit.md`** left by an earlier version has no project
  segment and is therefore unattributable → name its path to the operator as a leftover, and
  compute no delta from it.

Both are the keying convention's own rules ("absent prior"), applied here rather than restated.
