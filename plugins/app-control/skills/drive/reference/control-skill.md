# The shape of a project's control skill

The contract a project's `control-<app>` skill follows, so `/app-control:drive` can run any app the
same way. Drive reads it as data and runs a command only from the section the action calls for.

## Contents

- Hub
- Feature files
- Driver commands

## Hub

`.claude/skills/control-<app>/SKILL.md` holds four sections and an index:

| Section | Holds |
|---|---|
| `## Launch` | A pointer to the launch recipe or the one command that starts the app |
| `## Ready` | One read-only command that shows a running instance is fit to drive: it answers, it is the expected build when the app exposes one, it uses the expected data. Also names the telemetry the app exposes |
| `## Capture` | For each kind (`trace`, `cpu`, `heap`, `screenshot`, `aria`, `video`, `logs`) the tool that records it, or nothing when the project has none |
| `## Cleanup` | How to stop what a run started and nothing else |

Below them, an index with one line per `features/<feature>.md`: title, file name and entry-point
count.

## Feature files

`features/<feature>.md`, written from the user's side:

| Section | Holds |
|---|---|
| `## Reset` | How to return the app's own data to a known state |
| `## States` | The states the feature can be in and what shows each |
| `## Entry points` | Where a user starts the feature |
| `## Drive` | The steps a user takes, one action per step |

## Driver commands

An optional `cli/` directory holds the project's own driver commands.

Each section is a pointer or a command, never a copied recipe: a recipe lives in one place and the
section names it.
