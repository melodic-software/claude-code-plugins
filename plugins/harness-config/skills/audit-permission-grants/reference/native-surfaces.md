# The built-in `/permissions` command: verification record

Detail behind the `/permissions` Boundary section in [SKILL.md](../SKILL.md). Each row is a
four-part record: the claim, the basis it rests on, the date it was checked, and the event that
makes it worth checking again. "The extraction" below is the `/harness-ops:inventory` extraction of
the installed 2.1.284 binary, 2026-09-29.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `permissions` is a built-in command, alias `allowed-tools`, described as "Manage allow and deny tool permission rules". User-invocable only (not model-invocable), not hidden, not gated | The extraction | 2026-09-29 | A release renames it, changes its alias, or changes its invocability |
| The commands reference documents `/permissions` as managing allow, ask, and deny rules for tool permissions | <https://code.claude.com/docs/en/commands>, as parsed by `/harness-ops:inventory --docs` on 2026-09-29 | 2026-09-29 | That row changes or is removed |

## Why the verdict is complementary

`/permissions` edits rules one at a time inside a session and does not judge whether a rule is
portable or survives auto mode. This skill judges exactly that and edits nothing, so the useful
order is to read the audit first and then make the change in the dialog or the file. The model
offers `/permissions` to the person because only the person runs it.
