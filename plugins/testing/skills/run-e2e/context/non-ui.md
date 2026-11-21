# Non-UI Live Testing Playbook

Per-surface mapping of change type to smoke-test invocation for non-UI code, read when
`/testing:run-e2e` runs for non-UI changes. UI changes route to `e2e.md`. Command shapes come from
`/toolchain:check`, never restated here.

## When this playbook applies

- Change touches a non-UI surface listed in the per-surface table below
- User asks "how do I live-test this?" for libs, MCP servers, hooks, scripts, infrastructure code
- `/verification:confirm outcome` chains into surface-specific smoke tests beyond unit/build pass

## Per-surface table

Invocation commands come from `/toolchain:check`; framework, project-naming, and fixture detail come from the consuming project's testing conventions.

| # | Surface class | Live-test pattern | Known gaps |
|---|---------------|-------------------|------------|
| 1 | Library code | Unit tests cover behavior; no live-test pattern needed (pure libs) | None |
| 2 | API app (in-process) | The project's in-process HTTP-test harness; shared-state fixture pattern when a process-global singleton forces it | Browser evidence handled via `e2e.md` when UI surfaces ship |
| 3 | E2E orchestrator | Orchestrator boots in-process via its testing builder; assert resource health + endpoints | None |
| 4 | Architecture rules | Run the project's architecture-test suite when touching project files or build infrastructure | None |
| 5 | Hooks + shell scripts | The project's shell-test convention (`*.test.sh` siblings) via its documented runner | Cross-platform: Git Bash only on Windows; tests may pass locally and fail in CI (see `/toolchain:check` bash context "CI-environment caveat") |
| 6 | MCP server (per-runtime unit tests) | Unit-level coverage of tool handlers + transport plumbing | No protocol-level smoke test. See MCP stdio handshake pattern below |
| 7 | MCP server stdio handshake | See "MCP stdio handshake" section below | No upstream harness; replace bespoke recipe if an official one ships |
| 8 | Infrastructure code and scripts in a language other than shell | The project's lint and test convention for that language, with its standard fixtures, when the project has suites | None |
| 9 | Running CLI, TUI or service (the `run` value of `e2e_driver`) | A CLI or TUI runs under a pseudo-terminal (the platform's PTY utility or the harness's own PTY support) so it sees a terminal; send the scenario's input, then save its transcript and exit code as evidence. A service is exercised over HTTP with `curl -sS -o <file> -w '%{http_code}'` per request, saving each status and body to a file | A full-screen TUI's redraws make a raw transcript hard to read; capture the final screen as well. Where no pseudo-terminal is available (common on Windows), report the gap instead of running without a terminal |

## MCP stdio handshake

When unit tests pass but the server fails to register, test the JSON-RPC `initialize` handshake:
a protocol-level smoke test that proves the server speaks MCP over stdio.

**Pattern (all runtimes):**

1. Spawn the server with stdio transport (subprocess; capture stdin/stdout)
2. Send a JSON-RPC `initialize` request on stdin (one line, `\n`-terminated)
3. Read one line from stdout; parse as JSON-RPC response
4. Assert `result.protocolVersion`, `result.serverInfo.name`, and `result.capabilities` match expected shape

**Request/response shapes:** read the `initialize` request and response schemas from the MCP spec,
not a copy here (the protocol is versioned). This recipe was written against the pinned `2025-06-18` revision
(<https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle>); check the current
revision via <https://modelcontextprotocol.io/specification/latest> and match the recipe to the
revision your server SDK actually implements. This smoke test applies only to a server that
still supports a revision defining the `initialize` handshake (legacy-only or dual-era). For the
revision that changed the handshake, see the spec changelog's major changes,
<https://modelcontextprotocol.io/specification/2026-07-28/changelog#major-changes>.

**Spawn:** build the server first, then run the built server directly from its project directory.
Skip a package-manager script or a run command that builds: either writes its own lines to stdout
before the server's response, and step 3 then parses the wrong line.

Wire as `*.handshake.test.<ext>` next to existing unit tests, run by the surface's existing harness.

**Recheck:** when an official MCP server-test harness ships, replace this bespoke recipe with the harness invocation.

## Cross-references

- `e2e.md`: UI surface; mandatory evidence artifacts (snapshot / screenshot / console / network / assertion)
- `/toolchain:check`: SSOT for per-ecosystem build/test/lint invocations (per context file)
- `/verification:confirm outcome`: composes this playbook into outcome reports when changes affect non-UI runtime
- The consuming project's testing conventions: naming, framework gotchas, test placement
