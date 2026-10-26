---
bump: patch
---

### Fixed

- **`audit` no longer requires a `Read(./.claude/settings.local.json)` deny.** The row is gone from the baseline in `reference/required-permissions.md`, and `context/procedures.md`, `reference/audit-checklist.md` and `SKILL.md` no longer call it part of the baseline. The standards repository's permission floor leaves the file off on purpose, because it holds personal project overrides and saved approvals, not credentials. A `Read` deny on it also blocks Edit and Write on the same path. When a session starts in a subdirectory, a relative rule does not reach the copy Claude Code keeps at the repository root. A project that keeps a secret in the file still carries the deny itself, and the audit still treats the file as secret-bearing when it inspects it. Category F's advice to move a token into the file now also names a project `Read` deny on it or a credential store, because the file keeps a secret out of git, not out of the session.

### Added

- **`reference/required-permissions.md` states how the baseline differs from the standards permission floor, and why.** Three sensitive-file rows use a `./` prefix where the floor uses the bare form. The engine matches rule strings exactly, so Category B now tells the model to report such a row as present when the bare spelling is in `permissions.deny`. The floor's wider deny list is something a project declares in its own rules. `git push` is an ask rule in the baseline and an allow rule in the floor, and the ask rule still prompts when both are present.
