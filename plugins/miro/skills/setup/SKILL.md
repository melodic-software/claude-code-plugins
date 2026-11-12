---
description: "Verify the Miro plugin without reading or exposing its API token. Use when: 'set up Miro', 'configure Miro', 'Miro setup', the Miro MCP server is unavailable, or a Miro tool reports an authentication error. Actions: check (read-only verification, default and only action. This plugin's entire configuration is native userConfig, so there is nothing an apply could write); check verify-api additionally authorizes one read-only API call."
argument-hint: "[check] [verify-api]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Guide the user through Claude Code's native configuration flow and verify that the bundled Miro MCP
server is available without reading, printing, or writing the sensitive token. The `miro_api_token`
option is optional in the manifest: the server starts without it, and a Miro tool call without a
token returns an error that says to run `/plugin configure miro@<marketplace>`. Claude Code
owns the secure credential storage.

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration is the native sensitive `userConfig` token, so `check` (default and only
action) verifies and reports, and reconfiguration routes through Claude Code's native flow. An
`apply` here would have nothing to write except the credential storage and `pluginConfigs` setup
must never touch. Non-interactive: the optional API probe runs only when `verify-api` is passed,
never from an in-flow question.

Official contracts:

- **Pointer**: when a step turns on how plugin options or default enablement behave, fetch
  [Plugins reference: User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
  and [Default enablement](https://code.claude.com/docs/en/plugins/manifest-reference#defaultenabled)
  live.

## Task

1. Check whether the `miro` plugin is enabled and whether its scoped MCP tools are present in the
   current tool inventory. Do not inspect settings files, environment variables, process arguments,
   debug logs, credential stores, or the token itself.
2. When the plugin is disabled, direct the user to enable `miro` through the `/plugin` interface or
   `claude plugin enable miro`. The token is entered afterward with `/plugin configure miro@<marketplace>`. Do not run
   either command for the user and do not hand-edit `pluginConfigs`. For a non-interactive install
   (CI, a fleet bootstrap, a scripted machine setup), point to the headless path below instead.
3. When the plugin is enabled but its tools are absent, report that startup or configuration failed.
   Direct the user to the `/plugin` Errors view and `/mcp`. An unset token is not a startup
   failure: the server runs and each tool call returns the configure instruction, so absent tools
   point to a different cause. A first launch that cannot install the server's npm dependencies
   (no `npm` on `PATH`, no network, a failed `npm ci`) is such a cause: the server exits, and its
   stderr names the cause and the one shell line that repairs it. To tell the user where to read
   that stderr, read the two sections below at run time and give the user the route they state;
   do not read the user's logs for them.
   - **Pointer**: for where a plugin MCP server's startup error is recorded, see
     <https://code.claude.com/docs/en/plugins/troubleshooting#server-is-configured-but-never-connects>
     and <https://code.claude.com/docs/en/debug-your-config#check-mcp-servers>.

   After configuration, require `/reload-plugins` or a new session before rechecking tool availability.
4. When the scoped Miro tools are present, report only that the server started. The server starts
   and lists its tools with no token, so tool presence proves neither that a token was supplied nor
   that it has API access. Say the token state is unchecked, and that `verify-api` detects an unset
   token.
5. Optional credential check, only when the invocation passed `verify-api` (the explicit opt-in;
   never offer it as an in-flow question): call the read-only `miro_list_boards` tool with
   `limit: 1`. Never create, update, or delete a board during setup.
   - Success verifies API access; report only the count returned, not board names, IDs, or URLs.
   - A tool error saying `miro_api_token` is not set means the token is unconfigured: report
     `token not set` and direct the user to `/plugin configure miro@<marketplace>`, then
     `/reload-plugins`. An authentication failure gets the same direction.
   - Network, rate-limit, or service failure is reported as a distinct degraded state; do not tell the
     user to replace a credential unless the response identifies authentication as the cause.

## Headless installation

For a non-interactive install, CI, a fleet bootstrap, or a scripted machine setup, seed the token
on the initial install instead of the interactive `/plugin` prompt. Three steps, all required:

```shell
claude plugin marketplace add <source> --scope <scope>
claude plugin install miro@<marketplace> -s <scope> --config miro_api_token=<token>
claude plugin enable miro -s <scope>
```

Both placeholders are bootstrap inputs, not lookups: before the first install there is no record
to read them from. `<marketplace>` is the name the catalog registers under when it is added, and
`<scope>` is the scope the bootstrap chooses: `user`, `project`, or `local`. Pass the scope
explicitly on all three commands and carry the same `<scope>` through them; never rely on a
command's default. Each command's scope flag spelling and default are read live:

- **Pointer**: when writing or debugging the bootstrap, fetch
  [`plugin marketplace add`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-marketplace-add),
  [`plugin install`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install) and
  [`plugin enable`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-enable) live.

Registering at `user` while
installing at `project` leaves the marketplace declaration out of the project's checked-in
settings, so a fresh clone or CI agent carries the enabled plugin with no registered marketplace
to resolve it from.

**The enable step is not optional.** This plugin ships `defaultEnabled: false`, so no `miro` tool
is available until the enable step runs. Pointer: [Default
enablement](https://code.claude.com/docs/en/plugins/manifest-reference#defaultenabled).
Passing the scope to `claude plugin enable` explicitly keeps the sequence deterministic in CI. A
bootstrap that stops after `install` looks
successful and delivers no tools.

**Rotating or clearing the token:** `/plugin configure miro@<marketplace>` (interactive, any
time) is the recommended rotation path regardless. It masks input, unlike anything passed on the
command line (see the security note below).

Headless, use a route the marketplace's plugin-reconfiguration convention gives in
[§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
(it owns the verified-version record), and apply the scope and failure-signal caveats in its
[§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
Read both sections and print what they give, the fallback route, its behavior on an
already-installed plugin and the scope to pass included, rather than only naming them, and
leave out the verified-version record.
For `miro_api_token`, take the preferred `claude plugin configure miro@<marketplace>` route, which
keeps the token off the command line: delete its values file afterwards, or pipe the value in from
your secrets manager. Do not rely on the install-rerun fallback for the token, since that
convention's record covers only a non-sensitive option. Either way, confirm the new token with
`verify-api` in a **fresh session** (or after `/reload-plugins`, as step 3 says); a session that
has done neither can still hold the old one, so never report an unobserved rotation. Never
uninstall to rotate either; that section links what an uninstall deletes, and a
`defaultEnabled: false` plugin reinstalls DISABLED, so a rotation ending at `install` delivers no
tools.

- **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
  when a saved value applies, fetch
  [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
  live.

**Security note:** passing the token as a CLI argument records it in shell history
(`.bash_history`, `.zsh_history`) and briefly exposes it in the process table
(`/proc/<pid>/cmdline`, `ps aux`) while the command runs, unlike the interactive `/plugin`
prompt, which masks input and touches neither surface. In CI/CD, route the value through your
secrets manager rather than inlining it literally.

## Output

Report one state: `disabled`, `server unavailable`, `server ready (token not checked)`,
`token not set`, `API access verified`, or `API verification degraded`. Include the exact next action when the state is
not verified.

Claude Code keeps sensitive option values in its own secure credential storage. Never read or
reveal the contents of wherever it keeps them.

- **Pointer**: when a user asks where the token is stored, fetch
  [Plugins reference: Where values are stored](https://code.claude.com/docs/en/plugins/manifest-reference#where-values-are-stored)
  live and give them its answer.

## Boundaries

- Do not read, echo, log, copy, or persist the token.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform
  setup contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the
  marketplace repository).
- Do not make a Miro API request without explicit confirmation.
- Do not invoke a mutating Miro tool during setup.
- Do not claim success from tool presence alone when the user requested API verification.
