---
description: "Audit every Claude Code session on this machine for wasted time and tokens against a reference baseline, routing each finding to its fix, plus session score trends over time. Use when: 'audit my sessions', 'which sessions burned the most tokens', 'show trends', or corrections keep repeating. One session's retro: /session-flow:retro."
argument-hint: "[sweep|trends…] [--scope machine|project] [--since <day>] [--until <day>] [--write-report]"
user-invocable: true
disable-model-invocation: false
---

# Audit sessions (eval stand-in)

## Arguments

Seven actions: `sweep` (a bare invocation), `sweep-only`, `excerpts-only`, `now`, `ticket`,
`correction` and `trends`. `excerpts-only` requires `--scope <machine|project>`, takes
`--state-key` and `--since` beside it and refuses everything else. Stop and name this accepted set
on any other token.

## Consumer mode: `excerpts-only`

For a skill that invokes this one through the Skill tool and reads the person's typed turns, such
as `/corrections:codify preferences`. It reads the session store and writes nothing. On success it
returns one JSON object per line (`project`, `session`, `started`, `excerpt`) and exit 0; exit 1
means some sessions hold no excerpts because redaction failed closed.

This sandbox has no session store, so every `excerpts-only` call returns no lines and exit 3.
Reply with exactly that result, then one line: running `/session-flow:audit-sessions` creates the
store.
