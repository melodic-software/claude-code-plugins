# app-control

Runs the project's real app and shows what it did. `/app-control:drive` launches and operates the
app, observes it, and records evidence. It never judges: the report holds actions, observations and
artifact paths, and the caller (`/verification:confirm`, a CI verdict job or a person) decides what
they mean.

## Skills

| Skill | What it does |
|---|---|
| `/app-control:drive` | Bare drive performs a feature's steps; `ready` reports what is reachable; `capture --kind <kind>` records one artifact; `cleanup` stops what the run started and checks the evidence survives; `--attach` reaches a process already running that the person named, in an interactive session only; `--unattended` asks nothing |
| `/app-control:map` | Bare map proposes what it would write; `create` discovers the repository, asks only what discovery left open, writes the control skill (hub, feature folders, config, driver CLI and an instruction-file pointer) and proves it once through drive; `--unattended` is a dry run that writes nothing and lists every open question with a recommendation |

Both skills are model-invoked, so other skills, scheduled runs and CI jobs call drive instead of the
project's own control skill, and map is the only writer of that control skill.

## How it finds the app's control skill

Drive looks for a project skill named `control-<app>`, then a plugin skill named
`<plugin>:control-<app>`, and reads either from disk without invoking it. With none, it uses the
bundled `run` skill when that skill resolves, else a project-type recipe. Its report says which.
[`reference/control-skill.md`](reference/control-skill.md) defines the shape of a
control skill, [`reference/evidence.md`](skills/drive/reference/evidence.md) the run directory and
report, and [`reference/project-types.md`](skills/drive/reference/project-types.md) the fallbacks.

This plugin has no settings file and no prerequisites: the tools drive runs come from the project's
control skill.

## Not yet in this plugin

Reading an `app-control.yaml` override, attaching to a process drive did not start, and checking
or refreshing an existing control skill.

## Attribution

`/app-control:map create` reauthors the create-and-prove flow of pstack's
`create-verification-skill` from [cursor/plugins](https://github.com/cursor/plugins) (MIT); the
record is [`docs/upstream/cursor-pstack.md`](../../docs/upstream/cursor-pstack.md).
