# Auditing a command

A `.claude/commands/x.md` file and a skill both produce `/x`; skills are the recommended form
because they support `reference/`, supporting files, and auto-load. When auditing a command, one
valid finding is "should this be a skill?" if it needs supporting files or auto-discovery. Grade
both forms against the pages linked below at audit time, never from memory.

## Categories

Every finding is one of three, and the return names all three:

- **errors**: a bug, or a false positive the component showed a user
- **improvements**: behavior the component should have
- **quality-of-life**: friction while using the component

A category with nothing found says `nothing found`. A return that names only the bug it found is incomplete.

## Read first

- The command `.md`: frontmatter and body, graded against the current field set on
  <https://code.claude.com/docs/en/skills#frontmatter-reference> (fetched at audit time, never
  from memory; the [commands page](https://code.claude.com/docs/en/commands) covers the legacy
  flat-file form).

## Check

- **Naming collisions**: a same-named skill wins over a command; flag shadowing.
- **Frontmatter**: argument handling, tool permissions.
- **Determinism & escape hatches**: same as any workflow, meaning reliable steps and a clean bypass.
- **Migration**: would it be better as a skill (supporting files, progressive disclosure,
  auto-trigger)?

## Reproduce

Invoke `/command` with representative args; confirm behavior and argument binding.
