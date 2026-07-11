# Lane: <dependency-root-lane-name>

TEMPLATE — copy into `.claude/tidy-lanes/<lane-name>.md` and replace every `<placeholder>`.

The dependency root of your stack: the core/domain/shared libraries everything else depends on. Tidyings here have the highest leverage and the highest blast radius — apply with the most discipline.

## Scope

```text
<libs-root>/<core-package>/**
<libs-root>/<domain-package>/**
<libs-root>/<core-package>.Tests/**       # include the tests beside the code they cover
```

## Watch-for patterns

Most likely to apply in this lane (cross-reference `reference/tidyings.md` for full definitions):

- **Beck #1 — Guard Clauses** — early returns over nested conditionals, especially in validation and result-chain helpers
- **Beck #2 — Dead Code** — unreferenced internal helpers, commented-out blocks, obsolete type aliases left over from past refactors
- **Beck #5 — Reading Order** — reorder members so the public API reads top-to-bottom; private helpers below the methods that call them
- **Beck #6 — Cohesion Order** — group related members (constructor → primary state → operations on that state)
- **Beck #8 / #9 — Explaining Variables / Constants** — name hard-to-read sub-expressions and magic values
- **<language-modernization-pattern>** — e.g. newer language syntax the codebase has adopted piecemeal (verify the project's language-version floor first)
- **<analyzer-driven-pattern>** — candidates your linters/analyzers already flag as suggestions

## Lane-specific extra exclusions

Beyond the global HARD/SOFT lists:

- **Public API surface** — anything downstream packages consume; renames/signature changes here are behavioral
- **<project-specific-protected-area>** — e.g. serialization contracts, wire formats, persisted schemas

## Verification commands

```bash
<build-command>          # e.g. dotnet build / npm run build / cargo build
<test-command>           # e.g. dotnet test / npm test / cargo test
<lint-command>           # e.g. dotnet format --verify-no-changes / npx biome check
```

## Conventional Commits type

`refactor:`. Example title: `refactor(<area>): <what was tidied>`.

## Preferred research sources

- <authority-on-your-language-idioms>
- <authority-on-your-framework>
