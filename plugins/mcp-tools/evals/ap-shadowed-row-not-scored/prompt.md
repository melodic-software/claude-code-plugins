---
description: "Scope precedence needs real user, local and project config files, which a --config run cannot stage (file rows are not precedence-checked), so the inventory is given in the prompt as the Phase 1 output (narration). P1 follows the checklist table: filesystem (unversioned npx) and mailer (@latest npx) FAIL, notes (docker floating tag) WARN, local github and fetch PASS; the project github row, shadowed-by:local, stays in the inventory with no findings; mailer gets P3 unverified; FAIL findings come before WARN; both footer kinds are carried into Coverage."
tags: [mcp-tools, audit-posture, outcome, floating-version, scope-precedence, narration, output-contract]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "P1 FAIL on filesystem and mailer, WARN on notes, PASS on local github and fetch; the shadowed project github row is listed but not scored; mailer is P3 unverified; FAIL rows precede WARN rows; the not-read and not-evaluated lines appear under Coverage."
---

/mcp-tools:audit-posture

Is it safe to run my MCP servers? The inventory script already ran on this machine; use its output below as the Phase 1 output instead of running it again, and give me the posture report.

| scope | name | effective | transport | launcher | package | pin | publisher | sandboxed | provided_by |
|---|---|---|---|---|---|---|---|---|---|
| local | github | yes | stdio | npx | @modelcontextprotocol/server-github@2025.4.8 | exact | @modelcontextprotocol | no | - |
| project | filesystem | yes | stdio | npx | @modelcontextprotocol/server-filesystem | floating-unversioned | @modelcontextprotocol | no | - |
| project | github | shadowed-by:local | stdio | npx | @modelcontextprotocol/server-github@latest | floating-tag | @modelcontextprotocol | no | - |
| user | fetch | yes | stdio | uvx | mcp-server-fetch==2025.4.7 | exact | pypi | no | - |
| user | mailer | yes | stdio | npx | postmark-mcp@latest | floating-tag | unscoped | no | - |
| user | notes | yes | stdio | docker | mcp/notes:latest | floating-tag | mcp | no | - |
| user | search | yes | http | remote | https://mcp.example.com | n/a | mcp.example.com | n/a | - |

```text
# source user ~/.claude.json found
# source local ~/.claude.json found
# source project ~/app/.mcp.json found
# source managed /etc/claude-code/managed-mcp.json absent
# source managed-settings /etc/claude-code/managed-settings.json absent
# not read: MDM/registry/plist policy
# not read: server-managed settings
# not read: claude.ai connectors
# not read: --mcp-config servers
# not read: plugin servers not passed as --config
# not evaluated: allowedMcpServers/deniedMcpServers (see /harness-config:audit)
# not evaluated: project approval in settings files (enabledMcpjsonServers, enableAllProjectMcpServers); only the ~/.claude.json project entry is read, so an unapproved project row shows approval-unknown
# not evaluated: file-scope rows are not checked for precedence against other scopes
# not evaluated: managed-settings.d drop-ins are merged by whole entry per name; key-level merging is not modeled
```
