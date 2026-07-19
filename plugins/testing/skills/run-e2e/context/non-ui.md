# Non-UI Live Testing Playbook

Per-surface mapping of change-type → smoke-test invocation for non-UI code. Complements `e2e.md` (browser-driven UI evidence). Cites `/toolchain:check` for command shapes — never restates, never drifts.

Load on-demand when `/testing:run-e2e` is invoked for non-UI changes. UI changes route to `e2e.md`.

## When this playbook applies

- Change touches a non-UI surface listed in the per-surface table below
- User asks "how do I live-test this?" for libs, MCP servers, hooks, scripts, infrastructure code
- `/verification:confirm outcome` chains into surface-specific smoke tests beyond unit/build pass

UI changes (Blazor / Razor / HTML / CSS / JS shipped to browser) MUST route to `e2e.md` instead — the UI evidence contract is mandatory there.

## Per-surface table

Invocation commands come from `/toolchain:check`; framework, project-naming, and fixture detail come from the consuming project's testing conventions.

| # | Surface class | Live-test pattern | Known gaps |
|---|---------------|-------------------|------------|
| 1 | Library code | Unit tests cover behavior; no live-test pattern needed (pure libs) | None |
| 2 | API app (in-process) | The ecosystem's HTTP-test harness (e.g. WebApplicationFactory); shared-state fixture pattern when a process-global singleton forces it | Browser evidence handled via `e2e.md` when UI surfaces ship |
| 3 | E2E orchestrator (e.g. Aspire AppHost) | Orchestrator boots in-process via its testing builder; assert resource health + endpoints | None |
| 4 | Architecture rules | Run the project's architecture-test suite when touching project files or build infrastructure | None |
| 5 | Hooks + shell scripts | The project's shell-test convention (`*.test.sh` siblings, bats) via its documented runner | Cross-platform — Git Bash only on Windows; tests may pass locally and fail in CI (see `/toolchain:check` bash context "CI-environment caveat") |
| 6 | MCP server (per-runtime unit tests) | Unit-level coverage of tool handlers + transport plumbing | No protocol-level smoke test — see MCP stdio handshake pattern below |
| 7 | MCP server stdio handshake | See "MCP stdio handshake" section below | No upstream harness; replace bespoke recipe if an official one ships |
| 8 | Python infrastructure / scripts | pytest (via `uv run` in uv-managed projects); standard fixtures | None |
| 9 | PowerShell (`*.ps1` / `*.psm1`) | PSScriptAnalyzer (lint); Pester when the project has suites | None |

## MCP stdio handshake

When unit tests pass but the server fails to register, the gap is the JSON-RPC `initialize` handshake — protocol-level smoke test that proves the server speaks MCP over stdio correctly.

**Pattern (all runtimes):**

1. Spawn the server with stdio transport (subprocess; capture stdin/stdout)
2. Send a JSON-RPC `initialize` request on stdin (one line, `\n`-terminated)
3. Read one line from stdout; parse as JSON-RPC response
4. Assert `result.protocolVersion`, `result.serverInfo.name`, and `result.capabilities` match expected shape

**Initialize request shape** (per MCP spec [modelcontextprotocol.io/specification/2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18)):

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": {"name": "smoke-test", "version": "0.0.0"}
  }
}
```

**Expected response shape:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-06-18",
    "capabilities": { "tools": {} },
    "serverInfo": { "name": "<server-name>", "version": "<server-version>" }
  }
}
```

**Per-runtime spawn:**

| Runtime | Spawn command (from the server's project directory) |
|---------|------------------------------------------------------|
| Node | `node dist/index.js` (after `npm run build`) |
| .NET | `dotnet run --project <ServerProject>.csproj --no-build` (after `dotnet build`) |
| Python | `uv run python -m <server_module>` |

Wire as `*.handshake.test.<ext>` next to existing unit tests; runner inherits the surface's existing harness (vitest for Node, xUnit for .NET, pytest for Python).

**Recheck:** when an official MCP server-test harness ships, replace this bespoke recipe with the harness invocation.

## Cross-references

- `e2e.md` — UI surface; mandatory evidence artifacts (snapshot / screenshot / console / network / assertion)
- `/toolchain:check` — SSOT for per-ecosystem build/test/lint invocations (per context file)
- `/verification:confirm outcome` — composes this playbook into outcome reports when changes affect non-UI runtime
- The consuming project's testing conventions — naming, framework gotchas, test placement
