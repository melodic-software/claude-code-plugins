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

Type-annotate every public function. Modules under `analytics/` must not import from `web/` — the
dependency runs one way only. Prefer `pathlib` over `os.path` in new code.

## How we review

Reviews are conversations, not gates. Ask questions freely. A reviewer who requests changes should
say what would satisfy them, not only what is wrong.

## Migration files

Every migration under `db/migrations/` must be reversible and must be tested against a copy of
production-shaped data before merge. Never edit a migration that has already been applied in any
environment — add a new one.

## Release process

Releases are cut on the first Tuesday of the month. The release manager rotates; see the schedule in
the team calendar.
