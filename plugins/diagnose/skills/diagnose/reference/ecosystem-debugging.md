# Per-ecosystem debugging conventions

Referenced from `/diagnose` Phase 1 ("Iterate on the loop itself" — `timing-injection`) and Phase 4 ("Instrument" — `logging` + `banned-output`; "Performance branch" — `perf-tooling`). Find your stack below; the universal principle is to wrap I/O and time sources at their seam and tag every probe with a unique `[DEBUG-<hex>]` prefix so cleanup is a single grep.

The rows below are idiomatic defaults, not policy. Where your project defines its own conventions — a mandated logger, a banned-symbols analyzer, a preferred benchmark harness — those win; read your project's `CLAUDE.md` / `.claude/rules` and tool config and honor them.

## .NET (`dotnet`)

- **logging** — Use the existing `ILogger` with the tag in the message — `_logger.LogDebug("[DEBUG-a4f2] {State}", state)`. Source-generated `[LoggerMessage]` is the production best practice, but ad-hoc debug-tag calls during a Phase 4 instrument pass are short-lived enough that the inline `LogDebug` form is acceptable — they get deleted in Phase 6.
- **perf-tooling** — Establish a baseline measurement: a timing harness, a `BenchmarkDotNet` micro-bench, `Stopwatch`, or an EF Core query plan via `dbContext.Database.GetDbConnection()`. Then bisect against the baseline.
- **timing-injection** — Inject `System.TimeProvider` (BCL) and use `Microsoft.Extensions.TimeProvider.Testing.FakeTimeProvider` in tests so timing is fully controlled. Apply the same principle to other I/O sources — wrap them at the seam where they enter the code so the loop can swap a deterministic stand-in.
- **banned-output** — Prefer the structured logger over raw `Console.WriteLine`: a raw console write bypasses structured-logging sinks (and any telemetry pipeline such as OTEL). If your project bans a console-output API via a banned-symbols analyzer, route every probe through `ILogger` instead — otherwise the probe is a build error.

## Python (`python`)

- **logging** — Prefix `logger.debug()` or `print()` with the `[DEBUG-<hex>]` tag.

## TypeScript (`typescript`)

- **logging** — Prefix `console.log()` with the `[DEBUG-<hex>]` tag.
