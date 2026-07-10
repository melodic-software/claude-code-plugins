# Server discovery configuration

Configuration consumed by Phase 1 to enumerate a project's MCP servers and their tool source files.
Repo-agnostic: nothing here assumes a specific directory layout or project.

## Scan root and server grouping

`discover.sh` scans the project (the git repository root, or the directory passed to `--path`) for the
per-language tool markers below, skipping vendor, build, and test paths. It emits one record per tool
(`Tool file`, `Tool`, `Tool line`), grouped under a best-effort **server label** derived from each
tool file's path — the nearest ancestor directory above a runtime/source folder (`node/`, `python/`,
`dotnet/`, `src/`), or the top-level directory otherwise. Pass `--path <dir>` to scope the audit to a
single server's directory.

## Languages

Per-language tool-discovery and extraction contracts. The `tool-marker`, `name-extraction`, and
`description-extraction` rules are upstream MCP-SDK conventions and are stable across projects. To
support an additional MCP SDK (Go, Rust, JVM), add a language entry following the same shape.

### python (FastMCP)

- **source-glob:** `**/*.py`
- **exclude-globs:** `**/.venv/**`, `**/__pycache__/**`, `**/*_test.py`, `**/test_*.py`
- **tool-marker:** `@mcp.tool`
- **name-extraction:** function name immediately following the `@mcp.tool` decorator
- **description-extraction:** function docstring (first triple-quoted string in body)

### typescript (`@modelcontextprotocol/sdk`)

- **source-glob:** `**/*.ts`
- **exclude-globs:** `**/node_modules/**`, `**/build/**`, `**/dist/**`, `**/*.test.ts`, `**/*.spec.ts`
- **tool-marker:** `server.tool(` or `server.registerTool(`
- **name-extraction:** first positional argument — string literal
- **description-extraction:** the `description` field (or second positional argument) — string literal

### dotnet (`ModelContextProtocol`)

- **source-glob:** `**/*.cs`
- **exclude-globs:** `**/bin/**`, `**/obj/**`, `**/*Tests/**`
- **tool-marker:** `[McpServerTool]`
- **name-extraction:** method name carrying the `[McpServerTool]` attribute
- **description-extraction:** `[Description]` attribute on the method
