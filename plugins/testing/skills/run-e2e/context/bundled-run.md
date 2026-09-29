# The bundled `run` skill: verification record

Detail behind the `## Native step` and `## Boundary` sections in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The `/verify` handoff keeps its own dated record in the body's Handoff
section.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `run` ships with Claude Code as a bundled skill: "Launch and drive your app to see a change working". `/verify` ("Build and run your app to confirm a code change does what it should, without falling back to tests or type checks") and `/run-skill-generator` ("Teach `/run` and `/verify` how to build and launch your project") ship beside it; the three infer the launch from the project type (CLI, server, TUI, browser-driven) without setup | The bundled skills list on <https://code.claude.com/docs/en/skills> | 2026-09-11 | The list changes, or a release note names any of the three |
| Its registration carries `menuDescription:"Launch this project's app to see your change working"` and `userInvocable` | String search of the installed 2.1.263 binary | 2026-09-11 | A release changes the registration |
| The commands table carries a `/run` row labeled Skill, "Launch and drive your project's app to see a change working, not only passing tests"; the page's legend above the table states that `/verify` runs only when the user invokes it (before 2.1.215 Claude could start it) | <https://code.claude.com/docs/en/commands>, the `/run` row and the bundled-skill legend | 2026-09-11 | The `/run` row changes, or the legend changes `/verify`'s invocability |
| Neither bundled skill captures evidence to a contract, and neither has a non-UI mode | The two descriptions above name launching, driving, building, and confirming; nothing names screenshots, response captures, logs as artifacts, or libraries, MCP servers, hooks, and scripts | 2026-09-11 | Either skill gains an evidence-capture or non-app target mode |
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
unchanged. One launch path runs per verification, never both.

## Presence

Bundled skills are gated by `disableBundledSkills`, `skillOverrides`, the host surface, and the
environment. Nothing here depends on `run` being present: every skip state in the Native step
falls back to this skill's own launch playbook, which is complete on its own.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which `run`
appears as a bundled skill. This record re-verifies the registration on the installed 2.1.263
binary by string search and reads the two pages named above, all on 2026-09-11.
