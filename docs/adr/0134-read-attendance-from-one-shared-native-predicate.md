# Read attendance from one shared native predicate

- Status: accepted
- Date: 2026-11-25
- Related: [ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md) (the per-plugin copies this ships through);
  [guardrails Unwatched sessions](../../plugins/guardrails/README.md#unwatched-sessions)

## Context

Whether a person attends a session decides real behavior: guardrails asks instead of denying a
destructive command or a settings write only then, and session-flow's observer catch-up arms only
then. Each reader carried its own rule. guardrails read `CLAUDE_CODE_SESSION_ATTENDED == 1`;
session-flow read `CLAUDE_CODE_ENTRYPOINT == cli`, which skips any attended surface whose
entrypoint reads another value. Neither
variable is on the Claude Code environment-variables page
([env-vars](https://code.claude.com/docs/en/env-vars), checked 2026-11-25). Observed on Claude Code
2.1.331: an interactive terminal session reads `ATTENDED=1`, `ENTRYPOINT=cli`; `claude -p` reads
`ATTENDED=0`, `ENTRYPOINT=sdk-cli`. An undocumented signal can change in any release, so its names
and values must live in one place.

## Decision

1. **One data file, `lib/session-attended.env`**, names the attended variable and its value, the
   entrypoint variable and the headless entrypoint list (`sdk-cli sdk-ts sdk-py`).
2. **Two thin readers hold only the rule**: `hook::session_attended` in `lib/session-attended.sh`
   and `sessionAttended(env)` in `lib/session-attended.mjs`. A session is attended when the attended
   variable equals the value and the entrypoint is not headless. The entrypoint can only veto. A
   missing, empty or malformed data file, or anything unexpected, reads unattended; neither reader
   throws or aborts under `set -u`. One fixture table, `lib/session-attended.fixtures.mjs`, drives
   both readers.
3. **Plugins take generated copies** through `scripts/shared-copies.txt`. guardrails (`refuse.sh`,
   `settings-write-ask.mjs`) and session-flow (`observer-catchup.sh`) read only the predicate.
   `settings-write-ask.mjs` imports it dynamically and denies when the import fails.
4. **Callers add only stricter vetoes after it.** guardrails asks only when the predicate holds and
   `GUARDRAILS_SESSION_UNWATCHED` is not `1`, so guardrails never becomes looser than before;
   `plugins/guardrails/hooks/attended-veto.test.sh` checks every case against the old rule.

## Alternatives considered

- **(a) The names as constants in both the `.sh` and the `.mjs` reader.** An upstream rename then
  takes two edits that can drift. Not chosen.
- **(b) One node module that bash callers spawn.** Adds a node process to every guarded tool call.
  Not chosen.
- **(c) Keep each plugin's own rule.** Leaves session-flow keyed to one entrypoint value and three
  places to update on drift. Not chosen.

## Consequences

- An Agent SDK session (`sdk-*` entrypoint) that reads `ATTENDED=1` now gets a deny from guardrails
  where it got an ask.
- Recheck when Claude Code documents an attended signal, or renames either variable or changes its
  values; the change is one edit to `lib/session-attended.env` and a sync.
- Readers that use `CLAUDE_CODE_ENTRYPOINT` to tell surfaces apart (plugin-profiles, harness-ops
  mod posture) are a different question and keep their own reads.
