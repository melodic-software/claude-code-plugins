---
description: 'Legacy audit 1. Asked to shorten AGENTS.md by moving sections into .claude/rules/, audit corrects the premise (a rule without paths: loads at launch like CLAUDE.md) and proposes only scoped moves. unscoped-no-saving reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, demote, unscoped-rule]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply corrects the premise before acting: a rule without paths: frontmatter loads at launch with the same priority as .claude/CLAUDE.md, so an unscoped move saves nothing and the glob is what produces the saving. It proposes path-scoped destinations with concrete globs (such as **/*.cs for C# naming, src/components/** for React components, **/*.test.ts for test files), reports sections with no narrower scope (Build and test, Directory layout, Formatting) as staying put with compression suggested in place, and edits no instruction file.'
---

/instruction-placement:audit: this AGENTS.md is too long. Just move the big sections into .claude/rules/ so it gets shorter.

The root `AGENTS.md` is the handbook below, and the root `CLAUDE.md` is the single line `@AGENTS.md`. There is no `.claude/rules/` directory yet. The tracked files are 140 `.cs` files under `src/Api/`, 38 `.tsx` files under `src/components/`, 52 `*.test.ts` files beside the code they cover, three services under `services/` (`billing`, `search`, `notify`), and 61 other files.

```markdown
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
anything else. Removing the commit is not sufficient, the value is compromised.

## C# naming

Interfaces are prefixed with `I`. Private fields use `_camelCase`. Async methods end in `Async`.
Public classes are `sealed` unless explicitly designed for inheritance.

## React components

Every component in `src/components/` is a function component. Props interfaces are named
`<Component>Props` and declared in the same file. Avoid default exports.

## Test files

Test files use the `*.test.ts` suffix and live beside the code under test. Tests must never hit the
network. Use the local stub server. Prefer table-driven tests for pure functions.

## New service checklist

Every new service under `services/` must ship with a health endpoint, a Dockerfile, and an entry in
the deployment manifest before it is merged.

## Directory layout

- `src/`: application code
- `services/`: deployable services
- `docs/`: documentation
- `scripts/`: build and maintenance scripts

## Formatting

Indent with two spaces. Maximum line length is 100 characters. Trailing commas in multi-line
literals.

## Billing module

The billing service owns its own retry policy. Do not add retries at the caller. A caller-side
retry on top of the service's own produces duplicate charges.
```

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
