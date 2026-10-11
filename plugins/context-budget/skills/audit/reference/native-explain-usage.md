# The bundled `explain-usage` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. Nothing here asserts the skill is present in any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `explain-usage` is a bundled skill: "Explain where this session's tokens went, with one simple chart in plain language", menu line "See where this session's tokens went, in plain words" | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29 (`bundled_skills` lane) | 2026-09-29 | A release renames or removes the skill, or changes its description |
| It is model-invocable and user-invocable, takes no argument hint, and is gated | The same extraction (`model_invocable`, `user_invocable`, `gated` all true) | 2026-09-29 | A release changes its invocability or its gate |
| It is undocumented on the commands page and no changelog entry names it, so the extraction is the only basis | [commands § All commands](https://code.claude.com/docs/en/commands#all-commands) and <https://code.claude.com/docs/en/changelog> read for the name (no anchor: the claim is an absence across every entry, so the whole page is the source) | 2026-10-11 | The commands page gains an `/explain-usage` row, or a release note names it |
| It explains the current session after the fact; nothing in its description measures a fresh session's startup payload, attributes built-in tools, or compares two configurations | The description above | 2026-09-29 | A release widens its description to startup cost or per-tool attribution |
| Its description names an explanation and a chart, not a file or settings write | The description above | 2026-09-29 | A release gives it an output file or a fix action |

## Why the verdict is complementary

Both answer "what is using my tokens". `explain-usage` explains one session, the current one, after
the fact and in plain words. This skill measures the fixed payload every session starts with, per
item, by A/B differencing headless sessions, and ledgers the measured delta of each lever. A person
asking where this session's tokens went is better served by the native explanation where it
resolves; startup cost, per-tool attribution, and before/after deltas stay here.

## Presence

We never assume a bundled skill is present: the routing reads "resolves in this session", never
"is available". What can remove, hide, or vary a bundled skill is read live at the pointer.

- **Pointer:** [skills § Bundled skills](https://code.claude.com/docs/en/skills#bundled-skills).
- **As of:** 2026-10-11.
- **Recheck trigger:** that section adds, removes, or renames a way a bundled skill can be turned
  off or hidden.
