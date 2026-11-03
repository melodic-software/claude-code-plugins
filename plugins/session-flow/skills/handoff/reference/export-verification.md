# Verification record: `/export`

This skill suggests `/export` to the person and never runs it, and gates the suggestion on the
command being available in the person's session. Our probes back this: on Claude Code 2.1.241
(2026-08-24), `claude --bare -p "/export <path>"` refused the command as unavailable in that
environment, and on 2.1.263 (2026-09-11) it registered as an interactive local-jsx command, not a
prompt, so the Skill tool never lists it. We found no switch that disables it.

- **Pointer**: for the `/export` command, see
  <https://code.claude.com/docs/en/commands#all-commands>; for the headless refusal and the
  invocation mode, the probes above.
- **As of**: 2026-09-29
- **Recheck trigger**: a Claude Code release note or the commands page adds an `/export` format or
  redaction flag, a headless or programmatic form, or an official conversation-sharing surface.
