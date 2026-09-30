# Re-runnable machine profile for setup skills

Record for
[#4666](https://github.com/melodic-software/claude-code-plugins/issues/4666),
a proposed host-fact store that would drive every plugin `setup` skill.

## Decision

**Superseded in part.** The design is now
[machine-profile-design](../specs/machine-profile-design.md) and the placement is
[ADR 0041](../adr/0041-place-the-machine-profile-as-a-claude-ops-skill.md): a skill in
`claude-ops`. Building the skill and any setup-contract or invocation-mode change stay
undecided until the owner rules on that design. Until then, no `machine-profile` skill
exists, no new plugin is added, and the rest of this record stands.

- **Option 1 (declined):** orchestrate by instruction. The profile would emit
  `/<plugin>:setup check` lines for the operator to type. That respects class
  (ii) and is unpaid operator cost, not a skill to ship.
- **Option 2 (declined):** split `check` from `apply` so `check` is
  model-invocable. Same ask as #4240. It needs a new invocation-mode class or
  an amendment to class (ii). The class list is the unit of extension.
- **Option 3 (declined):** relax `disable-model-invocation` on `check` only.
  Same effect as option 2 with less structure.

**Claim (original park, before the design document):** a re-runnable machine profile that discovers host facts once and
drives the fleet's setup skills is not implementable without amending
invocation-mode class (ii) and touching every setup skill; do not build it
until #4240 records that unblock. Host discovery stays inside each plugin's
`setup`. If the idea returns after that unblock, it is a `claude-ops` skill
that feeds `machine-health`'s declared-configuration drift check, never a
second host-fact store.
**Basis:** origin/main at this record: 58 plugin-level `plugins/*/skills/setup/SKILL.md`
files, all `disable-model-invocation: true`.
`docs/conventions/invocation-mode/README.md` class (ii) and the
invocation-reach invariant (a `true` skill cannot be invoked by any other
skill). No `machine-profile` token in `plugins/` or `docs/`.
`machine-health` already owns a `config` category for declared-configuration
drift. #4240 is open on the same gate.
**As of:** 2026-09-28.
**Recheck:** #4240 records an invocation-mode class (ii) amendment, or a
maintainer funds a `claude-ops` skill whose only job is a read-only host-fact
document that `machine-health` consumes.

## Rationale

- Naive orchestration is impossible today: every setup skill is model-hidden.
- Options 2 and 3 are a fleet contract change (58 skills plus
  `validate-plugin-contracts.mjs`), not a claude-ops slice.
- A parallel host-fact document would compete with `machine-health` instead of
  feeding it.
- Per-plugin setup already owns prerequisite logic and versions with the
  plugin. Absorbing that into one driver is the gotcha the issue named.

## Revisit when

- #4240 lands a recorded unblock (new class or a class (ii) amendment), or
- an operator go names a read-only host-fact document with no setup-skill
  orchestration.

## Prior requests

- #4666 (2026-09-28): wayfind design item; parked here. Coordinated with #4240.
