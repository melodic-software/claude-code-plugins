# Lane: <polyglot-services-lane-name>

TEMPLATE — copy into `.claude/tidy-lanes/<lane-name>.md` and replace every `<placeholder>`.

Services written outside the primary language — MCP servers, sidecars, workers. These see fewer reviews than mainline code, so idiom drift and dead code accumulate; but each ecosystem needs its own verification commands.

## Scope

```text
<services-root>/<service-a>/**       # e.g. a TypeScript MCP server
<services-root>/<service-b>/**       # e.g. a Python worker
```

## Watch-for patterns

- **Beck #2 — Dead Code** — linters surface candidates (ruff F401/F841, biome unused-import)
- **Beck #9 — Explaining Constants** — inline port numbers, retry counts, endpoint paths
- **Formatter drift** — `<formatter-check-command>` per ecosystem; tidy in passing
- **Idiom modernization** — `<ecosystem-a-pattern>` (e.g. Promise chains → async/await), `<ecosystem-b-pattern>` (e.g. os.path → pathlib). Verify each ecosystem's version floor first
- **F-3 — Rename** — internal symbols whose names drifted from behavior

## Lane-specific extra exclusions

Beyond the global HARD/SOFT lists:

- **MCP tool schemas** — tool names, input/output schemas: behavioral, never tidy
- **Cross-service wire contracts** — message shapes, queue payloads: behavioral
- **<generated-code-glob>** — generated clients/stubs; regenerate, don't hand-tidy

## Verification commands

```bash
# One block per ecosystem in scope:
<ecosystem-a-build-lint-test>        # e.g. npx biome check && npm test
<ecosystem-b-build-lint-test>        # e.g. ruff check . && pytest
```

## Conventional Commits type

`refactor:`. Example title: `refactor(<service>): <what was tidied>`.

## Preferred research sources

- <authority-per-ecosystem>
