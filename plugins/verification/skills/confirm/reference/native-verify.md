# The bundled `verify` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row states what this skill
relies on, in our words, with a pointer to the section to read live, the date it was checked, and
the event that makes it worth checking again.

| What we rely on | Pointer | As of | Recheck trigger |
|---|---|---|---|
| `verify` is a bundled skill, and what answers to `/verify` in a given repository can change, so this skill never triggers it and never assumes which one resolves | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29. Pointer: what can take its place is read at [skills: run and verify your app](https://code.claude.com/docs/en/skills#run-and-verify-your-app) | 2026-09-29 for the extraction; 2026-10-11 for the skills section | A release renames or removes it or changes its description, or that section changes what can take its place |
| The person runs it; we offer it and never delegate to it | Same extraction (`disable_model_invocation` true, `user_invocable` true); for its invocability, see the `/verify` note under <https://code.claude.com/docs/en/commands#all-commands> | 2026-09-29 | A release changes its invocability, or the commands page note changes |
| A project can teach the bundled run and verify skills how to drive its app, so a project that has done so gets a more reliable drive; what `/run-skill-generator` records and which skills follow it are read live | Pointer: [skills: run and verify your app](https://code.claude.com/docs/en/skills#run-and-verify-your-app) | 2026-10-11 | That section changes what `/run-skill-generator` records or which skills follow it |
| A consumer can hide it, so the Boundary section never assumes it resolves | For the settings that turn bundled skills off or hide one, see <https://code.claude.com/docs/en/skills#bundled-skills> and <https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings> | 2026-10-11 | The skills page changes either setting |

## Why the verdict is complementary

`/verify` observes the running app and answers "does it behave". This skill answers "did we build
the right thing": it gates on the mechanical pass, matches the change against the plan or intent,
names the couplings the change leans on, and renders the verdict from a fresh context. A drive of
the running app is one kind of evidence inside that verdict, so the model offers `/verify` to the
person as an addition when the change has a runtime surface, and never as a substitute.
