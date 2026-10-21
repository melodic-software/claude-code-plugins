# app-control

Runs the project's real app and shows what it did. `/app-control:drive` launches and operates the
app, observes it, and records evidence. It never judges: the report holds actions, observations and
artifact paths, and the caller (`/verification:confirm`, a CI verdict job or a person) decides what
they mean.

## Skills

| Skill | What it does |
|---|---|
| `/app-control:drive` | Bare drive performs a feature's steps; `ready` reports what is reachable; `capture --kind <kind>` records one artifact; `cleanup` stops what the run started and checks the evidence survives; `--unattended` asks nothing |

The skill is model-invoked, so other skills, scheduled runs and CI jobs call it instead of the
project's own control skill.

## How it finds the app's control skill

Drive looks for project skills named `control-<app>`. With none, it uses the bundled `run` skill
when that skill resolves, else a project-type recipe. Its report says which.
[`reference/control-skill.md`](skills/drive/reference/control-skill.md) defines the shape of a
control skill, [`reference/evidence.md`](skills/drive/reference/evidence.md) the run directory and
report, and [`reference/project-types.md`](skills/drive/reference/project-types.md) the fallbacks.

This plugin has no settings file and no prerequisites: the tools drive runs come from the project's
control skill.

## Not yet in this plugin

Reading an `app-control.yaml` override, attaching to a process drive did not start, and mapping
features.
