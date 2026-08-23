# Engineering handbook

Instructions for anyone working in this repository.

## Build and test

Run `make build` to compile and `make test` for the full suite. The suite must be green before you
open a pull request.

## Git safety

Never force-push a shared branch. Never run `git reset --hard` on `main`. If history needs
rewriting, open an issue first and get a second pair of eyes on the plan.

## Secrets

Never commit a `.env` file or any credential. If a secret reaches a commit, rotate it before doing
anything else — removing the commit is not sufficient, the value is compromised.

## C# naming

Interfaces are prefixed with `I`. Private fields use `_camelCase`. Async methods end in `Async`.
Public classes are `sealed` unless explicitly designed for inheritance.

## React components

Every component in `src/components/` is a function component. Props interfaces are named
`<Component>Props` and declared in the same file. Avoid default exports.

## Test files

Test files use the `*.test.ts` suffix and live beside the code under test. Tests must never hit the
network — use the fixture server. Prefer table-driven tests for pure functions.

## New service checklist

Every new service under `services/` must ship with a health endpoint, a Dockerfile, and an entry in
the deployment manifest before it is merged.

## Directory layout

- `src/` — application code
- `services/` — deployable services
- `docs/` — documentation
- `scripts/` — build and maintenance scripts

## Formatting

Indent with two spaces. Maximum line length is 100 characters. Trailing commas in multi-line
literals.

## Billing module

The billing service owns its own retry policy. Do not add retries at the caller — a caller-side
retry on top of the service's own produces duplicate charges.
