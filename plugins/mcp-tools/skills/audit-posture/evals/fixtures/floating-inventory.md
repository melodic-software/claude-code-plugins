# Fixture: inventory with floating versions

Output of `inventory.sh --date 2026-09-26` for a fictional configuration, rendered as a table
(the script emits the same columns tab-separated, after a `# mcp-posture inventory 2026-09-26`
header line). Treat this table as the Phase 1 output; do not run the script.

| scope | name | effective | transport | launcher | package | pin | publisher | sandboxed |
|---|---|---|---|---|---|---|---|---|
| local | github | yes | stdio | npx | @modelcontextprotocol/server-github@2025.4.8 | exact | @modelcontextprotocol | no |
| project | filesystem | yes | stdio | npx | @modelcontextprotocol/server-filesystem | floating-unversioned | @modelcontextprotocol | no |
| project | github | shadowed-by:local | stdio | npx | @modelcontextprotocol/server-github@latest | floating-tag | @modelcontextprotocol | no |
| user | fetch | yes | stdio | uvx | mcp-server-fetch==2025.4.7 | exact | pypi | no |
| user | mailer | yes | stdio | npx | postmark-mcp@latest | floating-tag | unscoped | no |
| user | notes | yes | stdio | docker | mcp/notes:latest | floating-tag | mcp | no |
| user | search | yes | http | remote | `https://mcp.example.com` | n/a | mcp.example.com | n/a |

Footer lines:

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
# not evaluated: allowedMcpServers/deniedMcpServers, enableAllProjectMcpServers, enabledMcpjsonServers (see /claude-config:audit)
# not evaluated: file-scope rows are not checked for precedence against other scopes
```
