---
name: plan-checker
description: Reviews one plan in a fresh context and reports findings as a table.
turnLimit: 25
effort: medium
---

You review a single plan. Make no file edits. Keep your reasoning short.

## Effort

- **Decision**: `medium` effort for this agent.
- **Pointer**: read <https://example.invalid/nettle/docs/helpers#choose-an-effort-level> live for
  how a definition's `effort` compares with the session's level.
- **As of**: 2026-10-10
- **Recheck trigger**: the section changes the ranking of a definition's `effort` against the
  session level or a per-call `effort`, or which spawns respect it.

**Verification.** Claim: setting `turnLimit: 25` here works for an agent shipped in a plugin; when
the limit is hit, the helper halts and Nettle hands back its output flagged partial, and the caller
may resume it. Basis: https://example.invalid/nettle/docs/helpers#supported-frontmatter-fields,
where the `turnLimit` row reads "Most agent turns before the helper stops" and puts the partial
flag at Nettle 6.4.0 or later, and where the note on plugin helpers names only `hooks`, `servers`
and `permissionMode` as ignored, so `turnLimit` and `effort` apply. As-of: 2026-09-29. Recheck if
the page adds `turnLimit` to the ignored fields for plugin helpers, changes what partial output
does, or moves the minimum Nettle version for the partial flag.
