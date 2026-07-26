---
name: setup
description: "Verify the Miro plugin without reading or exposing its API token. Use when: 'set up Miro', 'configure Miro', 'Miro setup', the Miro MCP server is unavailable, or a Miro tool reports an authentication error. Actions: check (read-only verification, default and only action — this plugin's entire configuration is native userConfig, so there is nothing an apply could write); check verify-api additionally authorizes one read-only API call."
argument-hint: "check [verify-api]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Guide the user through Claude Code's native configuration flow and verify that the bundled Miro MCP
server is available without reading, printing, or writing the sensitive token. Claude Code prompts for
the required `miro_api_token` when the plugin is enabled and owns its secure credential storage.

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration surface is the native sensitive `userConfig` token, so `check` (default and only
action) verifies and reports, and reconfiguration routes through Claude Code's native flow — an
`apply` here would have nothing to write except the credential storage and `pluginConfigs` setup
must never touch. Non-interactive: the optional API probe runs only when `verify-api` is passed,
never from an in-flow question.

Official contracts:

- <https://code.claude.com/docs/en/plugins-reference#user-configuration>
- <https://code.claude.com/docs/en/plugins-reference#default-enablement>

## Task

1. Check whether the `miro` plugin is enabled and whether its scoped MCP tools are present in the
   current tool inventory. Do not inspect settings files, environment variables, process arguments,
   debug logs, credential stores, or the token itself.
2. When the plugin is disabled, direct the user to enable `miro` through the `/plugin` interface or
   `claude plugin enable miro`. Claude Code's native prompt collects the required token. Do not run
   either command for the user and do not hand-edit `pluginConfigs`. For a non-interactive install
   (CI, a fleet bootstrap, a scripted machine setup), point to the headless path below instead.
3. When the plugin is enabled but its tools are absent, report that startup or configuration failed.
   Direct the user to the `/plugin` Errors view, then to the native configuration prompt for `miro`.
   After configuration, require `/reload-plugins` or a new session before rechecking tool availability.
4. When the scoped Miro tools are present, report that the server started and the token was supplied;
   do not claim that the token has valid API access merely from tool discovery.
5. Optional credential check — only when the invocation passed `verify-api` (the explicit opt-in;
   never offer it as an in-flow question): call the read-only `miro_list_boards` tool with
   `limit: 1`. Never create, update, or delete a board during setup.
   - Success verifies API access; report only the count returned, not board names, IDs, or URLs.
   - Authentication failure directs the user back to Claude Code's native configuration prompt.
   - Network, rate-limit, or service failure is reported as a distinct degraded state; do not tell the
     user to replace a credential unless the response identifies authentication as the cause.

## Headless installation

For a non-interactive install — CI, a fleet bootstrap, a scripted machine setup — seed the token
on the initial install instead of the interactive `/plugin` prompt. Three steps, all required:

```shell
claude plugin marketplace add <source>
claude plugin install miro@<marketplace> -s <scope> --config miro_api_token=<token>
claude plugin enable miro -s <scope>
```

Both placeholders are bootstrap inputs, not lookups: before the first install there is no record
to read them from. `<marketplace>` is the name the catalog registers under when it is added, and
`<scope>` is the scope the bootstrap chooses — `user`, `project`, or `local`; `install` defaults
to `user` when the flag is omitted. Use the same `<scope>` in every command of the sequence.

**The enable step is not optional.** This plugin ships `defaultEnabled: false`, so it installs
DISABLED — the install seeds the token but leaves the MCP server, and therefore every `miro` tool,
unavailable until it is enabled ([Default enablement](https://code.claude.com/docs/en/plugins-reference#default-enablement),
which also notes `claude plugin enable` auto-detects the scope when `-s` is omitted; passing it
explicitly keeps the sequence deterministic in CI). A bootstrap that stops after `install` looks
successful and delivers no tools.

**Fresh-install-only:** `--config` seeds a value only on a fresh install. Re-running it against
an already-installed `miro` does not update the stored token. To rotate or clear the token later,
use `/plugin configure miro` (interactive, any time), or headlessly:

```shell
claude plugin list                                  # read the CURRENT scope for miro
claude plugin uninstall miro -s <scope>
claude plugin install miro@<marketplace> -s <scope> --config miro_api_token=<new-token>
```

Never re-run `install --config` against an existing install expecting it to take effect. Read the
scope from `claude plugin list` and carry that SAME `-s <scope>` through both commands — both
default to `user`, so omitting it against a `project`- or `local`-scope install removes a
different record than the one that is loading and reinstalls at a scope that does not load,
leaving the old token in use. For a `project`- or `local`-scope install, run both commands from
that project directory, since those scopes resolve against the current project.

**Security note:** passing the token as a CLI argument records it in shell history
(`.bash_history`, `.zsh_history`) and briefly exposes it in the process table
(`/proc/<pid>/cmdline`, `ps aux`) while the command runs — unlike the interactive `/plugin`
prompt, which masks input and touches neither surface. In CI/CD, route the value through your
secrets manager rather than inlining it literally.

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
