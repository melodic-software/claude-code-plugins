#!/usr/bin/env bash
# A plugin repo whose mcp-kit script reconnects failed MCP servers one at a time, and a one-release
# changelog whose only item adds a native command that reconnects them all at once.
set -euo pipefail
mkdir -p plugins/mcp-kit/.claude-plugin plugins/mcp-kit/scripts
printf '{"name":"mcp-kit","version":"0.1.0","description":"MCP helpers"}\n' >plugins/mcp-kit/.claude-plugin/plugin.json
cat >plugins/mcp-kit/scripts/reconnect-servers.sh <<'SH'
#!/usr/bin/env bash
# Reconnect every MCP server that failed to connect, one server at a time, because Claude Code
# offers no command that retries them all.
set -euo pipefail
for server in "$@"; do
  claude mcp reconnect "$server"
done
SH
cat >changelog.md <<'MD'
# Claude Code changelog

<Update label="2.1.284" description="September 28, 2026">
  * Added `/mcp reconnect all` in the interactive terminal to retry every MCP server that failed to connect or needs authentication at once
</Update>
MD
git init -q
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "chore: scaffold"
