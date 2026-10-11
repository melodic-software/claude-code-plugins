# The built-in `/insights` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row holds our decision,
the pointer to read live, the date it was checked, and the event that makes it worth checking
again.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| Treat `insights` as an ungated, user-invocable built-in with model invocation disabled, so this skill offers it and never runs it | Probe: the `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.insights`), observed 2026-09-29 | 2026-10-11 | A release renames or removes `insights`, or changes its invocability or adds a gate |
| Offer `/insights` for cross-session usage analytics; read what the report covers and where it is unavailable live | The `/insights` row of [Commands § All commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | That row changes what the report covers or where it runs, or disappears |
| Read report additions from the release notes, not from memory | [Changelog § 2.1.281](https://code.claude.com/docs/en/changelog#2-1-281) | 2026-10-11 | A release note changes what the report covers |

## Why the verdict is complementary

`/insights` is cross-session usage analytics: a report over many sessions, with no scoring
dimensions and no path into the repo's rules or memory. This skill scores one session or handoff
chain against fixed quality dimensions, checks feedback-memory regressions, and codifies learnings
behind approval. `trends` mode is the nearest overlap, and it still reads this plugin's own score
history rather than usage telemetry, so the skill offers `/insights` beside it rather than
replacing either.
