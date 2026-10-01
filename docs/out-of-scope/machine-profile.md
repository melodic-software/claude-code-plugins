# Re-runnable machine profile for setup skills

Record for
[#4666](https://github.com/melodic-software/claude-code-plugins/issues/4666).

## Decision

The design is ratified: [machine-profile-design](../specs/machine-profile-design.md), placed as a
`claude-ops` skill by
[ADR 0041](../adr/0041-place-the-machine-profile-as-a-claude-ops-skill.md). The skill is built as
`claude-ops` `machine-profile`. Only the following stays rejected or held:

- **Setup contract change (declined):** no setup skill is changed and
  `validate-plugin-contracts.mjs` is untouched.
- **Invocation-mode class (ii) change (held):** the setup skills stay
  `disable-model-invocation: true`. Splitting `check` from `apply`, relaxing the flag on `check`,
  or adding a class would each be a fleet contract change across every `setup` skill. The profile
  relies on reproduction and relay instead.
- **Orchestration by instruction (declined):** the profile does not emit `/<plugin>:setup check`
  lines for the operator to type.

## Rationale

- Every setup skill is model-hidden, so the profile cannot drive them directly.
- Changing class (ii) is a fleet contract change, not a `claude-ops` slice.
- Per-plugin setup owns prerequisite logic and versions with the plugin; the profile reads host
  facts and does not absorb that logic.

## Revisit when

The built profile shows a check that the existing wrappers and reproduction cannot cover. The
class (ii) decision is tracked with #4240.
