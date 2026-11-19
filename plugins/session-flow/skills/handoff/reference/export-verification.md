# Verification record: `/export`

This skill suggests `/export` to the person and never runs it, and gates the suggestion on the
command being available in the person's session. We treat it as an interactive built-in that the
Skill tool cannot invoke and a headless run cannot reach.

- **Probe record**: the `export` → `session-flow:handoff` entry of `docs/native-surfaces.md` in
  this plugin's marketplace repository holds the headless refusal, the invocation mode, and the
  trigger that reopens this decision.
- **Pointer**: when deciding whether `/export` can run headless or take a format or redaction
  flag, fetch the `/export` row of
  [Commands § All commands](https://code.claude.com/docs/en/commands#all-commands) live.
