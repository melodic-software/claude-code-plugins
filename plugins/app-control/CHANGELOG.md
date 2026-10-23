# Changelog

All notable changes to the `app-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-10-23

### Added

- `/app-control:drive` gains an attended-only `--attach`: it asks before each attach to a
  running process the person named, refuses under `--unattended` or with no person present and
  records the step as blocked, and runs any elevated attach only through a script it shows first.
- Four eval cases: ask before attaching, refuse with no one present, refuse under `--unattended`,
  and elevation through a shown script.

## [0.1.0] - 2026-10-21

### Added

- `drive` skill: launches and operates the project's app, observes it and records evidence, and
  never judges. Actions: bare drive, `ready`, `capture --kind <kind>` and `cleanup`, plus an
  `--unattended` mode that asks nothing and writes a fixed report a later job can read.
- It finds the project's `control-<app>` skill and falls back to the bundled `run` skill or a
  project-type recipe, and the report says which.
- `reference/control-skill.md` (the shape of a project's control skill), `reference/evidence.md`
  (the run directory, `report.md` and the `report.json` fields) and `reference/project-types.md`
  (the fallback recipes).
- Evals: four cases for the fallback line, a capability gap, a verdict-free report and an
  instruction found in app text.
