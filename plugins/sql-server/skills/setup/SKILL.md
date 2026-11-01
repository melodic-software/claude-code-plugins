---
description: "Check or set up the sql-server read-only MCP server: Node.js, the config file against its schema, the server copy in the plugin data directory, and a claude mcp add command per environment that names credentials by reference. Use when: 'set up sql-server', 'register a database for the agent', 'check my sql-server config', 'connect Azure SQL Database'. Actions: check (default) | apply."
argument-hint: "[check|apply] --config <path> [--environment <name>]"
user-invocable: true
disable-model-invocation: true
---

## What this sets up

A registration is one stdio server bound to one environment of one config file (design:
[ADR 0086](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0086-bound-the-sql-server-read-tier-by-a-read-only-principal-and-fixed-registrations.md)).
The plugin ships no server in its own `.mcp.json`; this skill installs a copy of the server into
`${CLAUDE_PLUGIN_DATA}/server` so registrations survive plugin updates, and registers it under a
name you choose.

The read-only database principal you create is the guarantee. A registration on a login that can
write is not read-only, whatever the reject list does. This skill creates no principal and no
config file; it checks the ones you made. Config shape and examples:
`${CLAUDE_PLUGIN_ROOT}/README.md` "Config"; Azure SQL Database:
`${CLAUDE_PLUGIN_ROOT}/reference/azure-sql-database.md`.

Arguments: the action (`check` when absent), `--config <path>` (required; ask for it once when
missing), and `--environment <name>` to limit the run to one environment. Every action is safe to
rerun. When the user asks for project scope, refuse it in your first reply, before any step, with
the reason `apply` step 3 gives, so a run that stops early still answers it.

## `check` (read-only)

1. Run, from the project directory:

   ```bash
   node "${CLAUDE_SKILL_DIR}/scripts/check-setup.mjs" --config <path> --data-dir "${CLAUDE_PLUGIN_DATA}" [--environment <name>]
   ```

   Report every row it prints in a PASS/FAIL/INFO table, with one remediation line per FAIL. Done
   when the table holds every row. Exit 1 means a FAIL row; exit 2 is a usage error to fix and rerun.
2. Remediations: `node` FAIL, install Node.js at the version the row names. `config` FAIL, edit
   the file at the place the message names (a literal password becomes `{ "env": "<VARIABLE>" }`;
   a config inside the project directory moves outside it). `server copy` or `server dependencies`
   FAIL, run `apply`. An `auth` row that says a variable is not set is INFO: set it in the
   environment Claude Code starts in, never in the config or the repository.
3. **Registrations.** For each environment, run `claude mcp get sql-<environment>` (or the name
   the user chose) and report INFO with what it shows, or "not registered". Done when each
   environment has a registration row.
4. **Grants.** For each registered environment whose `query` tool is in your tool list, call it
   once per database in the environment's list with
   `SELECT permission_name FROM fn_my_permissions(NULL, 'DATABASE')` and once with
   `SELECT s.name, p.permission_name FROM sys.schemas AS s CROSS APPLY fn_my_permissions(s.name, 'SCHEMA') AS p`.
   Report FAIL for a permission that starts with `INSERT`, `UPDATE`, `DELETE`, `EXECUTE`, `ALTER`
   or `CREATE`, or is `CONTROL`, `TAKE OWNERSHIP` or `IMPERSONATE`, with the remediation "remove
   that grant from the principal"; list the rest as INFO. With no such tool, report INFO "grants
   not checked: register the environment and rerun check in a fresh session". This covers grants
   at database and schema scope in the listed databases only: a grant on a single object, or in
   another database on the server, does not show. Done when each registered environment has a
   grants row.

Modify nothing in `check`.

## `apply`

1. Run `check`. Stop on a `node` or `config` FAIL and report it: `apply` cannot fix either.
2. **Install the server copy.** Run:

   ```bash
   node "${CLAUDE_SKILL_DIR}/scripts/install-server.mjs" --data-dir "${CLAUDE_PLUGIN_DATA}"
   ```

   It copies the server into `${CLAUDE_PLUGIN_DATA}/server` and runs `npm ci` there, or prints
   `unchanged:` when that copy already holds this version and its dependencies. Done when it prints
   `installed:` or `unchanged:` and exits 0; on exit 1, report its error and stop.
3. **Register.** Rerun `check` and show each `register <environment>` row's command. Each one
   registers `sql-<environment>` at user scope; the name is yours to change, and so is `--scope
   local`. Refuse `--scope project`: a registration lives only where the agent cannot edit it, and
   the repository is not such a place. Credentials are registered by reference (`--env
   'NAME=${NAME}'`), never by value; the `claude mcp get` readback below and the grants call in
   `check` step 4 are what confirm a credential arrived. The commands are for a POSIX shell.
   Skip an environment whose registration row already shows the same command and arguments, and
   report it as already in place; when that row shows different ones, show both and leave the
   change to the user. Run each other command only after the user confirms it (ADR 0086 section 3
   asks for that confirmation, so `apply` never registers unattended), then run
   `claude mcp get <name>` and report what it shows. Done when every confirmed registration has a
   `claude mcp get` readback.
4. **Readback.** Report the version `install-server.mjs` printed, each registration's readback and
   the check table from step 3. Leave the grants check of `check` step 4 to a fresh session, and
   tell the user to start one before relying on the registration.

## Output

What was already in place, what changed (the server copy's version, each registration made), what
was skipped or refused, and each FAIL with its remediation.

## Boundaries

- Never write a config file, a credential, or a project-scope registration.
- Never print a credential value; the scripts print variable names only.
- Never create or alter a database principal or grant: those stay with the database owner.
- Writes only `${CLAUDE_PLUGIN_DATA}/server` (built in `server.next` and swapped in) and, after
  confirmation, the user's own MCP registrations.

## Upstream record

- MCP scopes and environment variable expansion in registrations:
  <https://code.claude.com/docs/en/mcp#environment-variable-expansion-in-mcp-json>, as of
  2026-11-01. Recheck when Claude Code changes how `claude mcp add --env` stores a value or which
  scopes expand `${VAR}`, or when a readback shows a literal `${NAME}` reaching the server.
- When an added MCP server becomes available to a session:
  <https://code.claude.com/docs/en/mcp#managing-your-servers>, as of 2026-11-01. Recheck when
  Claude Code changes how `claude mcp add` takes effect, or when a registration's tools appear in
  the session that added it.
- Persistence of `${CLAUDE_PLUGIN_DATA}` across plugin updates:
  <https://code.claude.com/docs/en/plugins/components#path-variables-and-persistent-data>, as of
  2026-11-01. Recheck when that section changes, or when `check` reports no server copy after an
  update that `apply` had installed.
