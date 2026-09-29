# Re-runnable machine profile for setup skills

Recorded park for
[#4666](https://github.com/melodic-software/claude-code-plugins/issues/4666),
a proposed host-fact store that would drive every plugin `setup` skill.

Status: unratified agent proposal. The owner has not ruled on this park; #4666 is open for that
decision. Until then it is not a settled rejection.

## Decision

**Park. Do not build.** No `machine-profile` skill in `claude-ops`, and no new
plugin.

- **Option 1 (declined):** orchestrate by instruction. The profile would emit
  `/<plugin>:setup check` lines for the operator to type. That respects class
  (ii) and is unpaid operator cost, not a skill to ship.
- **Option 2 (declined):** split `check` from `apply` so `check` is
  model-invocable. The per-plugin form shipped in `actionlint`, `biome-format`,
  `go-format` and `markdown-format` (a separate model-invocable `check` skill beside the
  manual `setup`) with no invocation-mode amendment; the class list in
  `docs/conventions/invocation-mode/README.md` is still three. Whether to keep that per-plugin split
  is an open owner question,
  [#4240](https://github.com/melodic-software/claude-code-plugins/issues/4240) question 2.
- **Option 3 (declined):** relax `disable-model-invocation` on `check` only.
  Same effect as option 2 with less structure.

**Claim:** a re-runnable machine profile that discovers host facts once and
drives the fleet's setup skills has no model-invocable path to them: all 58
plugin `setup` skills are `disable-model-invocation: true`, which
`scripts/validate-plugin-contracts.mjs` requires. The model-invocable host
checks are `actionlint:check`, `biome-format:check`, `go-format:check` and
`markdown-format:check` (one per plugin) and `claude-ops:prerequisites`, a
read-only report over the `prerequisites.json` that 7 plugins declare. Host discovery stays inside each
plugin's `setup`. If the idea returns, it is a `claude-ops` skill that feeds
`machine-health`'s declared-configuration drift check, never a second
host-fact store.
**Basis:** origin/main: 58 plugin-level `plugins/*/skills/setup/SKILL.md`
files, all `disable-model-invocation: true`, required at
`scripts/validate-plugin-contracts.mjs:189-190`. The `check` skill of each of
those four plugins and `plugins/claude-ops/skills/prerequisites/SKILL.md`
set `disable-model-invocation: false`. `docs/conventions/invocation-mode/README.md`
still lists three classes, class (ii) among them, and the invocation-reach
invariant (a `true` skill cannot be invoked by any other skill). No
`machine-profile` skill or plugin under `plugins/`. `machine-health` already
owns a `config` category for declared-configuration drift.
**As of:** 2026-09-29.
**Recheck:** a setup skill drops `disable-model-invocation: true`
(`git grep -L 'disable-model-invocation: true' -- 'plugins/*/skills/setup/SKILL.md'`
lists a file; it lists none today), or a maintainer funds a `claude-ops` skill
whose only job is a read-only host-fact document that `machine-health`
consumes.

## Rationale

- Naive orchestration is impossible today: every setup skill is model-hidden.
- Option 3 changes the contract `validate-plugin-contracts.mjs` enforces on all
  58 setup skills. Option 2 adds a `check` skill to each setup plugin that
  lacks one. Neither is a claude-ops slice.
- A parallel host-fact document would compete with `machine-health` instead of
  feeding it.
- Per-plugin setup already owns prerequisite logic and versions with the
  plugin. Absorbing that into one driver is the gotcha the issue named.

## Revisit when

- a `setup` skill becomes model-invocable (the Recheck condition above), or
- the owner rules on the check/setup split in #4240 (question 2), or
- an operator go names a read-only host-fact document with no setup-skill
  orchestration.

## Prior requests

- #4666 (2026-09-28): wayfind design item; parked here. Coordinated with #4240.
