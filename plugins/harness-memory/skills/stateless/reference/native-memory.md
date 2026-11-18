# The built-in `/memory` command: verification record

Detail behind the `/memory` Boundary section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. "The extraction" below is the `/harness-ops:inventory` extraction of the
installed 2.1.284 binary, 2026-09-29.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `memory` is a built-in command described as "Edit CLAUDE.md files and memory settings". User-invocable only (not model-invocable), not hidden, not gated | The extraction | 2026-09-29 | A release renames or removes it, or changes its invocability |

The documented basis is a pointer, not a row: the offer names `/memory` for a toggle or a look at
the saved entries only while the commands reference lists the command as doing each of those.

- **Pointer**: when deciding whether to offer `/memory`, fetch the `/memory` row of
  [All commands](https://code.claude.com/docs/en/commands#all-commands) live.

## Why the verdict is complementary

`/memory` changes the setting from inside one session, at whatever scope its dialog writes. This
skill reports the setting's effective value across every scope, including the env var that
overrides it, sets both levers for a durable disable, and deletes the store on request. The model
offers `/memory` to the person because only the person runs it.
