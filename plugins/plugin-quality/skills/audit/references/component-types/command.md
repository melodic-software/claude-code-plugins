# Auditing a command

Growable stub. Note: custom commands have been **merged into skills** — a `.claude/commands/x.md`
and a skill both produce `/x`. Commands still work, but skills are recommended (they support
`references/`, supporting files, and auto-load). When auditing a command, one valid finding is
"should this be a skill?" if it needs supporting files or auto-discovery.

## Read first

- The command `.md`: frontmatter (argument-hint, allowed-tools) and body.

## Check

- **Naming collisions** — a same-named skill wins over a command; flag shadowing.
- **Frontmatter** — argument handling, tool permissions.
- **Determinism & escape hatches** — same as any workflow: reliable steps, clean bypass.
- **Migration** — would it be better as a skill (supporting files, progressive disclosure,
  auto-trigger)?

## Reproduce

Invoke `/command` with representative args; confirm behavior and argument binding.
