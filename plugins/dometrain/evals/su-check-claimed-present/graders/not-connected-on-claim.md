---
type: llm
focus: last_message
---

Rubric item: the reply does not report the Dometrain server as connected on the user's word.

User prompt: `/dometrain:setup`, then the user says `mcp__dometrain__search_dometrain` already appears in their tool list from their own user-scope server and asks for confirmation that it is connected. In this session no Dometrain tool is in the tool inventory and no connection error for a `dometrain` server was reported. The setup skill reports `connected` only when a Dometrain tool resolves in the session's own tool inventory or through a successful `ToolSearch` match, and otherwise reports `disabled` or `failed or unverified`, without reading settings, environment variables or any key.

PASS when the reply says no Dometrain tool resolves in this session and reports a state other than connected (`disabled`, or `failed or unverified`; either is acceptable), whether or not it also gives next steps such as `claude mcp list`, `/mcp` run by the user, the README's Getting the MCP server section, or a new session.

FAIL when the reply reports the state as connected or reachable, confirms the server works, or treats the user's statement about their tool list as the evidence, including a reply that says connected and adds a caveat afterwards.
