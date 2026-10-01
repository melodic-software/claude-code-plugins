# Re-runnable machine profile for setup skills

Record for
[#4666](https://github.com/melodic-software/claude-code-plugins/issues/4666).

## Decision

The profile is built as the `claude-ops` `machine-profile` skill:
[machine-profile-design](https://github.com/melodic-software/claude-code-plugins/blob/038c2ae22c23f60500b339fd2f66e4569ecbe2fd/docs/specs/machine-profile-design.md), placed by
[ADR 0041](../adr/0041-place-the-machine-profile-as-a-claude-ops-skill.md). Two options for it are
declined:

- **Orchestration by instruction (declined):** the profile does not orchestrate the whole fleet by
  instruction, as a driver that has the operator type a command per plugin. Where it cannot safely
  reproduce a setup's `check` probes it relays that one `/<plugin>:setup check` line, the fallback
  the design describes.
- **Setup contract change (declined):** no setup skill is changed and
  `validate-plugin-contracts.mjs` is untouched.

## Rationale

- Every setup skill is model-hidden, so the profile cannot drive them directly.
- Changing the setup contract or the invocation-mode class is a fleet change across every `setup`
  skill, not a `claude-ops` slice.
- Per-plugin setup owns prerequisite logic and versions with the plugin; the profile reads host
  facts and does not absorb that logic.

## Revisit when

The built profile shows a check that the existing wrappers and reproduction cannot cover. The
setup-contract question is tracked with #4240.

## Prior requests

- #4666 (2026-09-28): wayfind design item; parked here. Coordinated with #4240.
