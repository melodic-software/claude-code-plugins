# Per-ecosystem debugging conventions

Referenced from `/debugging:debug` Phase 1 ("Phase 1 exit check", `timing-injection`) and Phase 4 ("Instrument", `logging` + `banned-output` + `perf-tooling`). Find your stack below; the universal principle is to wrap I/O and time sources at their seam. Every `logging` example below carries the session marker that the skill's Phase 6 cleanup rule defines.

The rows below are idiomatic defaults, not policy. Where your project defines its own conventions, those win: a mandated logger, a banned-symbols analyzer, a preferred benchmark harness. Read your project's `CLAUDE.md`, its `.claude/rules/` project rules, and tool config, and honor them.

## .NET (`dotnet`)

- **logging**: Use the existing `ILogger` with the tag in the message: `_logger.LogDebug("[DEBUG-a4f2] {State}", state)`. Source-generated `[LoggerMessage]` is the production best practice, but ad-hoc debug-tag calls during a Phase 4 instrument pass are short-lived enough that the inline `LogDebug` form is acceptable. They get deleted in Phase 6.
- **perf-tooling**: Establish a baseline measurement: a timing harness, a `BenchmarkDotNet` micro-bench, `Stopwatch`, or an EF Core query plan via `dbContext.Database.GetDbConnection()`. Then bisect against the baseline.
- **timing-injection**: Inject `System.TimeProvider` (BCL) and use `Microsoft.Extensions.Time.Testing.FakeTimeProvider` (NuGet: `Microsoft.Extensions.TimeProvider.Testing`) in tests so timing is fully controlled. Apply the same principle to other I/O sources: wrap them at the seam where they enter the code so the loop can swap a deterministic stand-in.
- **banned-output**: Prefer the structured logger over raw `Console.WriteLine`: a raw console write bypasses structured-logging sinks (and any telemetry pipeline such as OTEL). If your project bans a console-output API via a banned-symbols analyzer, route every probe through `ILogger` instead. Otherwise the probe is a build error.

## Python (`python`)

- **logging**: Prefix `logger.debug()` or `print()` with the `[DEBUG-<hex>]` tag.
- **timing-injection**: Pass a clock into the code under test, or freeze it in the test with a clock-faking library (`freezegun`, `time-machine`). For order and randomness, run with `pytest-randomly` and replay a failure with the seed it printed (`--randomly-seed=<n>`, or `last`); it also reseeds `random` per test. For the network, run with `pytest-socket`'s `--disable-socket` so any real connection fails loudly instead of flaking. Pointers: <https://github.com/spulec/freezegun>, <https://time-machine.readthedocs.io/>, <https://github.com/pytest-dev/pytest-randomly#readme>, <https://github.com/miketheman/pytest-socket#readme>. As of: 2026-10-06. Recheck trigger: a plugin renames the flag or seed form used here, or a clock library is retired.

## TypeScript (`typescript`)

- **logging**: Prefix `console.log()` with the `[DEBUG-<hex>]` tag.
- **timing-injection**: In unit tests, use the runner's fake timers (Jest `jest.useFakeTimers()`, Vitest `vi.useFakeTimers()`) and advance time explicitly instead of sleeping. In Playwright, control the page's clock with `page.clock`; fix `Date.now` with `setFixedTime` first, and reach for `install` plus `runFor` or `fastForward` only when timers must fire. Mock the network at the seam with `page.route` so the loop never depends on a live backend. Pointers: <https://jestjs.io/docs/timer-mocks>, <https://vitest.dev/guide/mocking/timers>, <https://playwright.dev/docs/clock>, <https://playwright.dev/docs/mock>. As of: 2026-10-06 (Playwright 1.63). Recheck trigger: a runner renames its fake-timer API, or Playwright changes the clock page's recommended first call.
