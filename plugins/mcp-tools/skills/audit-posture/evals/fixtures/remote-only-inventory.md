# Fixture: remote-only inventory

Output of `inventory.sh --date 2026-09-26` for a fictional configuration whose servers are all
remote, rendered as a table (the script emits the same columns tab-separated, after a
`# mcp-posture inventory 2026-09-26` header line). Treat this table as the Phase 1 output; do not
run the script.

| scope | name | effective | transport | launcher | package | pin | publisher | sandboxed |
|---|---|---|---|---|---|---|---|---|
| managed-settings | docs | yes | http | remote | `https://docs.example.com` | n/a | docs.example.com | n/a |
| project | tracker | yes | http | remote | `https://mcp.tracker.example.com` | n/a | mcp.tracker.example.com | n/a |
| user | events | yes | sse | remote | `https://events.example.com:8443` | n/a | events.example.com | n/a |

Footer lines:

```text
# source user ~/.claude.json found
# source local ~/.claude.json absent
# source project ~/app/.mcp.json found
# source managed /etc/claude-code/managed-mcp.json absent
# source managed-settings /etc/claude-code/managed-settings.json found
# not read: MDM/registry/plist policy
# not read: server-managed settings
# not read: claude.ai connectors
# not read: --mcp-config servers
# not read: plugin servers not passed as --config
# not evaluated: allowedMcpServers/deniedMcpServers, enableAllProjectMcpServers, enabledMcpjsonServers (see /claude-config:audit)
# not evaluated: file-scope rows are not checked for precedence against other scopes
```
