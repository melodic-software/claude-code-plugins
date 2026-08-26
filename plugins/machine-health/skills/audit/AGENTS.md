# machine-health audit skill: contributor conventions

Maintainer conventions for this skill live in [`README.md`](README.md); the sections below say
when to read each one.

## Layout: semantics vs implementation

Before adding or moving anything under `references/` or `scripts/`, read
[README.md, "Separation of semantics from implementation"](README.md#separation-of-semantics-from-implementation):
OS-agnostic content belongs in `references/shared/`, per-OS detection in `references/<os>/`,
and adding a new OS must be "populate two folders", never a refactor of the skill.
