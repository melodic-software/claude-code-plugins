# The bundled `run` skill: verification record

Detail behind the `## Native step` and `## Boundary` sections in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The `/verify` handoff keeps its own dated record in the body's Handoff
section.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `run` ships with Claude Code as a bundled skill, with `/verify` and `/run-skill-generator` beside it, and the first two infer the launch from the project without setup | [Extend Claude with skills § Run and verify your app](https://code.claude.com/docs/en/skills#run-and-verify-your-app) | 2026-10-11 | That section changes which skills it lists or how they find the launch |
| `run` is registered as a bundled skill with no invocation-control field, so Claude can invoke it on its own | Probe: the invocation-mode evidence line, dated 2026-09-11 (Claude Code 2.1.263), on the `run` x `testing:run-e2e` row of `docs/native-surfaces/records.json` | 2026-09-11 | A new extraction or binary search changes that evidence line |
| The commands reference lists `/run` as a bundled skill, and `/verify` runs only when the user invokes it | [Commands § All commands](https://code.claude.com/docs/en/commands#all-commands), the `/run` row and the legend above the table | 2026-10-11 | The `/run` row changes, or the legend changes `/verify`'s invocability |
| Neither bundled skill captures evidence to a contract, and neither has a non-UI mode | Our reading of the section in the first row: it names launching, driving, building, and confirming; nothing names screenshots, response captures, logs as artifacts, or libraries, MCP servers, hooks, and scripts | 2026-10-11 | Either skill gains an evidence-capture or non-app target mode |
| `run` defers to a project skill that already covers launching the app; a project skill named `run` is a legitimate target of that deferral | String search of the installed 2.1.284 binary: the `run` registration description contains "First looks for a project skill that already covers launching the app". The named-`run` half rests on the evidence line dated 2026-09-11 (2.1.263) on the `run` x `testing:run-e2e` row of `docs/native-surfaces/records.json` | 2026-09-29 (binary); 2026-09-11 (named `run`) | A release changes the registration description, or the store row's evidence line changes |

## Why the verdict is complementary and the integration is wrap

The verdict is complementary because the surfaces overlap without one replacing the other: `/run`
launches the project so a change can be looked at, while this skill's job is the record. It checks
prerequisites, drives UI and API flows, and captures evidence under the contract in
[e2e.md](e2e.md), then hands off. Its non-UI smoke lane ([non-ui.md](non-ui.md)) has no native
counterpart at all.

The integration is wrap: where the app's start is not governed by the consuming project's
orchestrator configuration, this skill composes `run` for the launch (the Native step in
[SKILL.md](../SKILL.md)) and layers the evidence contract on top. Where an orchestrator governs the
start, or the target has no app to launch, the step is skipped and the orchestrator path runs
unchanged. One launch path runs per verification, never both, and an app that is already
running is not launched again.

## Presence

Which bundled skills a session has, and the settings that turn them off, are
[Extend Claude with skills § Bundled skills](https://code.claude.com/docs/en/skills#bundled-skills)
(as of 2026-10-11; recheck when that section changes what makes a bundled skill unavailable).
Nothing here depends on `run` being present: every skip state in the Native step falls back to
this skill's own launch playbook, which is complete on its own.

## Extraction record

The probe rows above rest on the observations their Basis cells name: the registry row's evidence
line from the 2.1.263 binary on 2026-09-11, and a string search of the installed 2.1.284 binary on
2026-09-29. The docs rows were re-read live on 2026-10-11.
