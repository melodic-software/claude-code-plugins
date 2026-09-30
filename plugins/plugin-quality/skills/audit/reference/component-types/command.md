# Auditing a command

A `.claude/commands/x.md` file and a skill both produce `/x`; skills are the recommended form
because they support `reference/`, supporting files, and auto-load. When auditing a command, one
valid finding is "should this be a skill?" if it needs supporting files or auto-discovery. Grade
both forms against the pages linked below at audit time, never from memory.

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

## Categories

- **Errors:** an argument that does not bind, or a command that shadows a skill of the same name.
- **Improvements:** supporting files or auto-discovery the command needs and only a skill provides.
- **Quality of life:** invocation friction (undocumented arguments, a failure the operator cannot see).
- **Standards:** the `seam-phrasing` and `untrusted-content` probes.
- **Emitted findings:** when the command reports findings to a user, sample those findings and grade each.

## Reproduce

Invoke `/command` with representative args; confirm behavior and argument binding.
