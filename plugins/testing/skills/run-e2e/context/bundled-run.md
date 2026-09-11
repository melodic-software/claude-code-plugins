# The bundled `run` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The `/verify` handoff keeps its own dated record in the body's Handoff
section.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `run` ships with Claude Code as a bundled skill: "Launch and drive your app to see a change working". `/verify` ("Build and run your app to confirm a code change works") and `/run-skill-generator` ("Teach `/run` and `/verify` how to build and launch your project") ship beside it; the three infer the launch from the project type (CLI, server, TUI, browser-driven) without setup | The bundled skills list on <https://code.claude.com/docs/en/skills> | 2026-09-11 | The list changes, or a release note names any of the three |
| Its registration carries `menuDescription:"Launch this project's app to see your change working"` and `userInvocable` | String search of the installed 2.1.263 binary | 2026-09-11 | A release changes the registration |
| The commands table carries no `/run` row; its `/verify` row states that `/verify` runs only when the user invokes it (before 2.1.215 Claude could start it) | <https://code.claude.com/docs/en/commands>, searched for the row | 2026-09-11 | A `/run` row appears, or the `/verify` row changes invocability |
| Neither bundled skill captures evidence to a contract, and neither has a non-UI mode | The two descriptions above name launching, driving, building, and confirming; nothing names screenshots, response captures, logs as artifacts, or libraries, MCP servers, hooks, and scripts | 2026-09-11 | Either skill gains an evidence-capture or non-app target mode |

## Why the verdict is complementary

`/run` launches the project so a change can be looked at. This skill's job is the record: it
checks prerequisites, starts the app through the consuming project's orchestrator configuration,
drives UI and API flows, and captures evidence under the contract in [e2e.md](e2e.md), then hands
off. Its non-UI smoke lane ([non-ui.md](non-ui.md)) has no native counterpart at all.

## Presence

Bundled skills are gated by `disableBundledSkills`, `skillOverrides`, the host surface, and the
environment. Nothing here depends on `run` being present: the orchestrator path is complete on
its own.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which `run`
appears as a bundled skill. This record re-verifies the registration on the installed 2.1.263
binary by string search and reads the two pages named above, all on 2026-09-11.
