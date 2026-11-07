---
description: 'Legacy audit 4. Asked to sweep a contributor guide, audit promotes its normative sections (no presence to lose), picks pointer or move per candidate, and routes the section already repeated in two other docs out as a deduplication call. migration-routed-out reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, promote, single-source-of-truth]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply sweeps CONTRIBUTING.md and separates normative content (Python conventions, Migration files) from tutorial, history and process prose (Getting set up, A short history, How we review, Release process). It notes that promote candidates are content Claude loads never, so they carry no presence to lose. It picks per candidate between a short path-scoped pointer to the document and a move with a pointer left behind, rather than always copying. Because the migration rules already appear in docs/database.md and db/README.md, it reports that section and routes it out as a deduplication decision rather than picking a winner.'
---

/instruction-placement:audit: check this contributor guide too, there's convention material buried in it.

The root `CONTRIBUTING.md` is below. The root `AGENTS.md` is 40 lines with nothing about Python or migrations, and the root `CLAUDE.md` is the single line `@AGENTS.md`. The repository tracks 220 `.py` files across the `analytics/` and `web/` packages and 48 files under `db/migrations/`. The migration rules in `CONTRIBUTING.md` also appear, reworded, in `docs/database.md` and in `db/README.md`.

```markdown
# Contributing

Thanks for your interest in the project. This guide covers how we work.

## Getting set up

Clone the repository, run `make bootstrap`, and you should have a working environment. If
`make bootstrap` fails on macOS, it is almost always a missing Xcode command-line tools install.

## A short history

The project started as an internal tool in 2021 and was open-sourced the following year. The
original architecture used a monolithic worker, which we split into services during the 2023
rewrite. That history explains some of the naming you will see in older modules.

## Python conventions

Type-annotate every public function. Modules under `analytics/` must not import from `web/`. The
dependency runs one way only. Prefer `pathlib` over `os.path` in new code.

## How we review

Reviews are conversations, not gates. Ask questions freely. A reviewer who requests changes should
say what would satisfy them, not only what is wrong.

## Migration files

Every migration under `db/migrations/` must be reversible and must be checked against a copy of
production-shaped data before merge. Never edit a migration that has already been applied in any
environment. Add a new one.

## Release process

Releases are cut on the first Tuesday of the month. The release manager rotates; see the schedule in
the team calendar.
```

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
