# machine-health audit skill: contributor conventions

Maintainer conventions for this skill live in [`README.md`](README.md); the sections below say
when to read each one.

## Layout: semantics vs implementation

Before adding or moving anything under `references/` or `scripts/`, read
[README.md, "Separation of semantics from implementation"](README.md#separation-of-semantics-from-implementation):
OS-agnostic content belongs in `references/shared/`, per-OS detection in `references/<os>/`,
and adding a new OS must be "populate two folders", never a refactor of the skill.

## Check scripts run two ways

Before writing or editing a check script, read
[README.md, "Dual-invocation scripts"](README.md#dual-invocation-scripts): every check emits a
single JSON object on stdout for Claude (schema in `references/shared/output-schema.md`) and
takes `-Human` for readable output, using `Write-Host` in that mode so structured emitters keep
working over pipelines.

## Checks are stateless; the orchestrator owns state

Before touching a check's inputs or anything involving `state/history.jsonl`, read
[README.md, "Stateless checks, stateful orchestrator"](README.md#stateless-checks-stateful-orchestrator):
checks take a current reading and return it, never reading `history.jsonl` directly; the
orchestrator (`Invoke-MachineHealthCheck.ps1`) hands them a history slice over stdin and owns all
trend, severity, timeout, remediation, and reporting logic.
