---
name: setup
description: "Configure and verify the Miro plugin without reading or exposing its API token. Use when: 'set up Miro', 'configure Miro', 'Miro setup', the Miro MCP server is unavailable, or a Miro tool reports an authentication error."
argument-hint: "(no arguments — interactive configuration and verification)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Guide the user through Claude Code's native configuration flow and verify that the bundled Miro MCP
server is available without reading, printing, or writing the sensitive token. Claude Code prompts for
the required `miro_api_token` when the plugin is enabled and owns its secure credential storage.

Official contracts:

- <https://code.claude.com/docs/en/plugins-reference#user-configuration>
- <https://code.claude.com/docs/en/plugins-reference#default-enablement>

## Task

1. Check whether the `miro` plugin is enabled and whether its scoped MCP tools are present in the
   current tool inventory. Do not inspect settings files, environment variables, process arguments,
   debug logs, credential stores, or the token itself.
2. When the plugin is disabled, direct the user to enable `miro` through the `/plugin` interface or
   `claude plugin enable miro`. Claude Code's native prompt collects the required token. Do not run
   either command for the user and do not hand-edit `pluginConfigs`.
3. When the plugin is enabled but its tools are absent, report that startup or configuration failed.
   Direct the user to the `/plugin` Errors view, then to the native configuration prompt for `miro`.
   After configuration, require `/reload-plugins` or a new session before rechecking tool availability.
4. When the scoped Miro tools are present, report that the server started and the token was supplied;
   do not claim that the token has valid API access merely from tool discovery.
5. Offer an optional credential check. Only after the user explicitly accepts, call the read-only
   `miro_list_boards` tool with `limit: 1`. Never create, update, or delete a board during setup.
   - Success verifies API access; report only the count returned, not board names, IDs, or URLs.
   - Authentication failure directs the user back to Claude Code's native configuration prompt.
   - Network, rate-limit, or service failure is reported as a distinct degraded state; do not tell the
     user to replace a credential unless the response identifies authentication as the cause.

## Output

Report one state: `disabled`, `server unavailable`, `server ready (credential not API-verified)`,
`API access verified`, or `API verification degraded`. Include the exact next action when the state is
not verified.

Sensitive values use the macOS Keychain, or `~/.claude/.credentials.json` on platforms where no
supported keychain is available. Never read or reveal either location's contents.

## Boundaries

- Do not read, echo, log, copy, or persist the token.
- Do not edit Claude Code settings or `pluginConfigs`.
- Do not make a Miro API request without explicit confirmation.
- Do not invoke a mutating Miro tool during setup.
- Do not claim success from tool presence alone when the user requested API verification.
