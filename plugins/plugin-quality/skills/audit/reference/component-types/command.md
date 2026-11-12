# Auditing a command

When auditing a command, one valid finding is "should this be a skill?" if it needs supporting
files or auto-discovery. Grade both forms against the pages linked below at audit time, never from
memory.

- **Pointer**: when comparing what a command file and a skill each produce and support, fetch
  [How a skill gets its command name](https://code.claude.com/docs/en/skills#how-a-skill-gets-its-command-name)
  live.

## Read first

- The command `.md`: frontmatter and body, graded against the current field set on
  <https://code.claude.com/docs/en/skills#frontmatter-reference> (fetched at audit time, never
  from memory; the [commands page](https://code.claude.com/docs/en/commands) covers the legacy
  flat-file form).

## Check

- **Naming collisions**: flag a command that shares its name with a skill, and say which one runs.
  When deciding which wins, fetch
  [Resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name)
  live.
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
