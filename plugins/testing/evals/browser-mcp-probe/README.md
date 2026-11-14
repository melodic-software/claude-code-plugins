# browser-mcp-probe

Environment probe for the MCP path of the browser lane
(`.github/workflows/pr-run-plugin-evals.yml`). `playwright-cli` cannot run inside
`claude plugin eval` Bash on Linux (ADR 0056, Findings, 2026-10-11), so this case drives Chromium
through the Playwright MCP server instead. Each grader records one fact; the score is not a quality
measure.

## What it loads

- `pw-mcp/`, a case-local plugin (`plugins: ["pw-mcp"]`), declares one MCP server, `playwright`.
  Its `start.sh` refuses any `playwright-mcp` on PATH other than the `@playwright/mcp` version the
  root `package.json` locks (0.0.83 when this case was written), and starts it headless on the
  Chromium the lane installs under `/opt/pw`, by path, so a version bump does not depend on a
  matching browser revision. The testing plugin itself ships no MCP server.
- The tools are `mcp__plugin_pw-mcp_playwright__browser_navigate`, `..._browser_take_screenshot`
  and `..._browser_close`, plus `Read`. No Bash.

## Run it on the lane

Dispatch `pr-run-plugin-evals` on the default branch with:

| Input | Value |
|---|---|
| `target` | `plugins/testing` |
| `case` | `browser-mcp-probe` |
| `allow-tools` | `mcp__plugin_pw-mcp_playwright__*` |
| `allow-real-servers` | `true` |

`allow-real-servers` adds `--allow-real-servers`, which starts the plugin's unmocked servers; the
`allow-tools` grant names their tools ([plugin evals](https://code.claude.com/docs/en/plugin-evals),
"Mock MCP servers" and "Grant tools", as of 2026-11-02). The server runs as the runner user,
outside the eval's sandbox.

## Reading the graders

- `evals-hidden-from-read` and `evals-hidden-from-browser` are browser-probe's canaries with this
  case's own values. The server runs outside the sandbox with unrestricted file access, so a fail of
  `evals-hidden-from-browser` means the MCP path can read the eval directory; it is a finding about
  the path, not a case defect.
- `screenshot-created` counts `mcp-shot.png` only if the run's created-file list includes what the
  server wrote in the workspace; `screenshot-reported` reads the server's own reply.
- `diag-tool-error` is reused from browser-probe unchanged; the other graders are browser-probe's
  with MCP tool names and this case's page titles.

The screenshot step passes an absolute path in the workspace, so it does not depend on the
server's working directory. UNVERIFIED until a measured run: that the eval passes `start.sh` a
PATH that holds `/opt/tools/node_modules/.bin`.
