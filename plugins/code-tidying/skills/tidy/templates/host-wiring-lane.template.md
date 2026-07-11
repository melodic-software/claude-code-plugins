# Lane: <host-wiring-lane-name>

TEMPLATE — copy into `.claude/tidy-lanes/<lane-name>.md` and replace every `<placeholder>`.

Hosting infrastructure: startup wiring, service registration, logging configuration, middleware pipelines, service defaults. Ordering is often load-bearing here — the safest tidyings are naming, dead code, and constants; treat any registration reordering as suspect.

## Scope

```text
<hosting-root>/**
<shared-defaults-package>/**
```

## Watch-for patterns

- **Beck #2 — Dead Code** — registrations for services that no longer exist, stale feature-flag branches
- **Beck #9 — Explaining Constants** — inline connection-string keys, header names, timeout literals → named constants
- **Beck #12 — Extract Helper** — repeated registration blocks across hosts → one extension method (only when call sites are truly identical)
- **Beck #14 — Explaining Comments** — non-obvious ordering constraints deserve a `// Why:` comment
- **<config-consolidation-pattern>** — duplicated configuration keys/sections across host projects

## Lane-specific extra exclusions

Beyond the global HARD/SOFT lists:

- **Registration/middleware ORDER is behavioral** — pipeline ordering, instrumentation ordering, and startup sequencing change runtime behavior; never "tidy" the order
- **<orchestrator-config>** — service-discovery / orchestration host wiring your verification cannot exercise end-to-end (SOFT — defer)

## Verification commands

```bash
<build-command>
<test-command>
<smoke-command>          # optional: whatever proves the host still starts (e.g. a health-check script)
```

## Conventional Commits type

`refactor:`. Example title: `refactor(hosting): consolidate logging template constants`.

## Preferred research sources

- <authority-on-your-hosting-framework>
- <authority-on-your-observability-stack>
