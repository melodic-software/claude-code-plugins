# Bound the SQL Server read tier by a read-only principal and fixed registrations

- Status: accepted
- Date: 2026-10-28
- Related: [#5940](https://github.com/melodic-software/claude-code-plugins/issues/5940) (the
  plugin request, its S1 to S7 and F1 to F10 requirements and its Evidence section) and
  [#9805](https://github.com/melodic-software/claude-code-plugins/issues/9805) (this record, slice
  1 of 7). Slice 2 builds the server, slice 4 measures the read controls and the process
  topology, slice 5 adds the setup skill, and the last slice is the write tier.

## Context

Developers want an agent to query SQL Server-family databases, local containers and shared remote
databases such as Azure SQL Database, without letting it change data or harm a shared server. No
plugin in this repository ships a database MCP server. #5940 sets the requirements and leaves five
design questions open. On 2026-10-24 the owner decided (Q96 on #5940) that the first release is
the read-only tier only, tested against a local SQL Server container and Azure SQL Database, and
that the recommendations be followed. The write tier (S4) is the last slice and is out of scope
here.

Three facts shape every answer below:

- Claude Code permission rules match MCP tools by server and tool name. A settings-file `mcp__`
  rule that has parentheses is skipped, so a rule cannot allow one SQL statement and ask for
  another through the same tool.
- The MCP specification tells a client to treat tool annotations as untrusted unless they come
  from a trusted server, so the read-only guarantee cannot rest on an annotation.
- On SQL Server, `READ_COMMITTED_SNAPSHOT` is off by default and plain reads take shared locks; it
  is on by default in Azure SQL Database. A read can block writers on one platform and not the
  other.

The Evidence section of #5940 reviews the existing servers: several rely on a regex or prefix check,
and one names a read-only database login as its real boundary. Deterministic SQL validation
misses some statements and rejects some valid ones (F8), so this record states which control is
the guarantee and labels the rest.

The plugin directory is `plugins/sql-server`. That follows the fleet's plain lower-kebab plugin
names (`miro`, `playwright`), with no `-mcp` suffix.

## Decision

### 1. The read guarantee and the server-side controls (S1, S2, S3, F8)

The boundary is a least-privilege read-only database principal the consumer creates: a login or
Entra identity whose database user holds read permissions only (no write, DDL or `EXECUTE`
grants) and exists only in the databases the registration may read. The database engine enforces
it whatever SQL text the agent sends. The plugin does not create the principal. The setup skill
reports the grants it can see, which is a check, not the boundary.

The table below labels each control. The first row is the consumer's principal; the plugin builds
every other row. A **guarantee** holds whatever SQL the agent sends, because the plugin's own code
or the engine enforces it. A **heuristic** holds only until the agent's SQL undoes or evades it.

| Control | What it addresses | Label | Why |
|---|---|---|---|
| Read-only principal | Data or schema change | guarantee | The engine refuses the statement; it is only as strong as the grants the consumer gives |
| Request timeout | A runaway query | guarantee | The plugin cancels the request on the client side |
| Streaming row cap with prompt cancel | A huge result; a paused partial read holding locks | guarantee | The plugin counts rows as they stream and cancels at the cap |
| Transaction check after each call: when `@@TRANCOUNT` is above 0, discard the connection | A transaction left open, with its locks, after a call returns | guarantee | The plugin runs the check after the agent's statement, on its own round trip |
| Rollback guard: each call starts with `IF @@TRANCOUNT > 0 ROLLBACK` | A transaction left open by an earlier call | guarantee | The plugin issues it before the agent's statement |
| Discard the connection after a timeout, cancel or error | Session state or a transaction carried to the next call | guarantee | A connection that ended abnormally is never reused |
| `SET XACT_ABORT ON` per call | A run-time error leaving a transaction open | heuristic | The agent's statement could turn it off unless the reject list catches it |
| Pinned isolation (`READ COMMITTED`) per call | Lock-heavy isolation levels | heuristic | A `SET` or a table hint in the statement overrides it |
| `SET LOCK_TIMEOUT` per call | Waiting forever on a lock (the default is `-1`) | heuristic | The agent's statement could reset it unless the reject list catches it |
| Single-statement reject list | Every statement other than one read, refused before it reaches the server | heuristic | It reads T-SQL text; the bypass list in #5940 is inferred, not tested |

The reject list accepts exactly one statement, and only a `SELECT`, optionally led by a `WITH`
common table expression. Every other statement kind is refused, `SET`, `USE`, `EXECUTE`,
`DBCC`, `WAITFOR` and explicit transactions included, with no list of them to keep current.
Inside the `SELECT` it refuses `INTO`, a user `OPTION (...)` clause, `OPENROWSET`, `OPENQUERY`
and `OPENDATASOURCE`, and lock-holding table hints (`HOLDLOCK`, `SERIALIZABLE`, `REPEATABLEREAD`,
`UPDLOCK`, `XLOCK`, `PAGLOCK`, `TABLOCK`, `TABLOCKX`). It runs on a tokenizer that skips
comments, string literals and bracketed identifiers, not on a regex over raw text. Its refusals
are clear errors; its misses fall through to the principal and the transaction check.

The server opens no wrapper transaction around a read; the statement runs in autocommit. Under
locking `READ COMMITTED`, the SQL Server default, the statement still holds its own shared locks
until it ends, so the row cap and the request timeout bound how long a read can block a writer.
A wrapper would add round trips and, per #5940's Evidence, hold back version-store cleanup, while
the principal already makes a rollback unnecessary for a read.

Slice 4 measures each heuristic and each timeout and cap against a local container with a
concurrent writer and sets the shipped defaults from the result. Until then the defaults are
provisional.

### 2. A fixed tool set per registration (S5, S7, F2)

Every registration exposes the same three tools: `query` (one read statement), `list_objects`
(schemas, tables and views) and `describe_object` (columns, keys and indexes). The server declares
the `tools` capability with `listChanged` false and returns the same list on every `tools/list`.
The MCP specification (revision 2026-07-28) says the list must not vary per connection or as a
side effect of other requests. No tool switches a profile, connects to another server, or adds or
removes tools.

A registration binds one environment, fixed by its launch arguments: one server and an allow-list
of databases on it. Each tool takes an optional `database` argument, which defaults to the first
database in the allow-list. A name outside the allow-list is refused before any connection
opens, and no argument names a server or an environment. An agent therefore cannot widen its
scope at runtime: reaching another environment takes another registration, made by a person. A
three-part name in a statement that points at another database on the same server is stopped
only by what that database lets the principal do, so the consumer must check the principal's
access in every database on the server, system databases included. The setup skill reports the
access it can see.

### 3. User-scope registrations from a setup skill (F7, F2, F5)

The plugin ships no server in its own `.mcp.json`. A plugin-shipped server gets the fixed name
`mcp__plugin_sql-server_<server>__<tool>`, and the plugin cannot ship one per consumer
environment without shipping organization-specific names (F4).

Slice 5's setup skill instead prints a `claude mcp add` command for each environment, under a
name the consumer chooses, and runs it after the consumer confirms. The scope is `user` (the
default) or `local`, both stored in `~/.claude.json`. Project scope is refused, because it puts
the registration in the repository's `.mcp.json`, a file the confined agent can write. The
command never carries a secret value: credentials reach the server from the consumer's own
environment. The server name, and so every permission rule and agent tool list written against
it, stays stable across plugin upgrades. Another MCP client (F5) registers the same stdio command
line.

`${CLAUDE_PLUGIN_ROOT}` changes with each plugin version, and neither it nor
`${CLAUDE_PLUGIN_DATA}` is substituted in a user-scope registration. So the setup skill installs
the server into the plugin's data directory (`~/.claude/plugins/data/<id>/`), which survives
updates, and writes that resolved absolute path into each registration. The setup skill's
`check` action reports an installed copy older than the plugin.

### 4. Language, driver, auth and process topology (F1, F10)

- **Language and runtime:** JavaScript (ES modules) on `node`, the runtime the fleet's hooks
  already require. A consumer who runs this fleet's hooks needs no new runtime.
- **Driver:** `tedious` used directly, with the plugin's own small pool, not `node-mssql`.
  The Evidence of #5940 records that `node-mssql` never resets session state when it reuses a
  pooled connection. Owning the pool keeps the rollback guard and the discard rule in one place.
- **Auth for the first release:** SQL login for the local container, and Entra through `tedious`'s
  `token-credential` type with a `DefaultAzureCredential` for Azure SQL Database. `tedious` asks
  the credential for a new token on each connect, and the pool closes idle connections, which
  keeps each connection short-lived. Whether a connection that stays busy past its token's expiry
  keeps working is unverified (#5940 lists Entra token refresh for long-lived pools as a gap).
- **Not covered in the first release:** Windows integrated and Kerberos auth. The `tedious`
  connection page names NTLM as its only Windows option, with no integrated or Kerberos mode.
  Azure SQL Managed Instance and other SQL Server hosts reachable over TCP are expected to work
  with the same two auth types, but the first release does not test them.
- **Process topology:** one stdio server process per registration per client session (each
  registration's normal launch), with a pool of at most two connections that closes idle ones,
  and an application name that marks agent sessions. A session with three registrations can
  therefore hold up to six connections. This is the default until slice 4 measures several concurrent processes
  against one database. A shared process is the only way to cap total load across sessions
  (F10). It would need an HTTP transport, client authentication and its own lifecycle, so it waits
  for a measured need.

### 5. A published, versioned config schema with connections by reference (F9, S6)

The config is one JSON file validated by a JSON Schema (draft 2020-12) published in the plugin at
`schemas/config.v1.schema.json`.

- A required integer `schemaVersion`, `1` for this release. An additive change keeps the
  version; a breaking change bumps it, and the server refuses a version it does not know.
- `defaults` for limits (request timeout, lock timeout, row cap), and `environments`, a map from a
  consumer-chosen name to one server, its port, its database allow-list, an `auth` block and
  optional limit overrides.
- `auth.type` is `sql-login` or `entra-default`. A `sql-login` names the environment variables that
  hold the user and the password. An `entra-default` takes an optional client id. No property
  holds a password or a connection string, the schema allows no unknown properties, and the
  server refuses a config that carries a literal password or connection string.
- A registration names its file and environment by launch argument (`--config <path>
  --environment <name>`). The server reads no other file, searches no project or repository
  directory, and refuses a `--config` path inside the project directory it was started in.

The tool surface uses MCP-standard terms only. Client-specific gating, such as Claude Code
permission rules or a hook on `mcp__<server>__query`, is documented as an optional adapter and is
never what the guarantee rests on.

## Alternatives considered

- **A parser or a rollback wrapper as the guarantee.** Rejected: both read SQL text or depend on
  it, and #5940's Evidence records read-only bypasses fixed in 2026 in a server that relied on
  such checks. They stay as labeled heuristics.
- **A profile-switching tool, or one tool set that varies by profile.** Rejected: switching a
  profile changes what a registration can reach at runtime (S5), and changing the tool list as a
  side effect of a call breaks the MCP specification and S7.
- **Plugin-shipped servers, alone or beside setup registrations.** Rejected: the names are fixed
  by the plugin, not chosen by the consumer (F7), and one shipped entry per environment would
  carry organization-specific names (F4).
- **.NET with `Microsoft.Data.SqlClient` and the ScriptDom parser.** Not chosen for the first
  release: it would add a .NET runtime beside the `node` the fleet's hooks already need, and a
  real parser still only strengthens a heuristic. It is the first candidate if integrated or
  Kerberos auth becomes a requirement.
- **Layered config discovery (user, project and repository files with precedence, as F3 asks).**
  Deferred: a repository file is writable by the agent the registration confines, so discovering
  it would let the agent widen its own scope. A later layer must not be able to add an
  environment or a database.
- **A shared server process.** Deferred to slice 4's measurement, as above.

## Consequences

- The README and the setup skill must say plainly that the read-only principal is the guarantee
  and that a registration on an over-granted login is not read-only, whatever the reject list
  does.
- Slice 2 builds the server, the three tools, the reject list and the schema. Slice 4 sets the
  timeout, lock timeout, row cap, isolation and pool defaults from measurement, and may change the
  topology. Slice 5 builds the setup skill and the Azure SQL Database docs.
- The first release does not cover integrated or Kerberos auth, layered config files, or a shared
  process. Each needs its own record or an amendment here.
- The write tier gets its own decision and must keep this record's read path intact: a separate
  write principal and a separate registration, per #5940's Evidence.
- Recheck when the MCP specification changes what `tools/list` may vary by, when Claude Code
  lets allow rules or settings-file rules match MCP tool arguments, or when `tedious` adds an integrated
  auth mode.

Sources read on 2026-10-28:
[MCP tools, revision 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools),
[Claude Code permissions](https://code.claude.com/docs/en/permissions),
[Claude Code MCP](https://code.claude.com/docs/en/mcp),
[plugin components](https://code.claude.com/docs/en/plugins/components),
[SET TRANSACTION ISOLATION LEVEL](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql),
[SET LOCK_TIMEOUT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-lock-timeout-transact-sql),
[SET XACT_ABORT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-xact-abort-transact-sql)
and the [tedious Connection API](https://tediousjs.github.io/tedious/api-connection.html).

## Amendment (2026-11-01): the write tier (S4)

[#9909](https://github.com/melodic-software/claude-code-plugins/issues/9909) (slice 7) adds the
write tier of #5940 S4: a write, where enabled, is approved by a person on every call, and Claude
Code enforces that in every permission mode. Sections 1 to 5 still hold for every read.

- **A separate write principal.** An environment may hold a `write` block whose `auth` names a
  second login or Entra identity, the only one with write grants. The read tools keep connecting
  as the read principal, so the read path still rests on section 1's read-only principal on every
  registration. The write principal gets its own pool. The server refuses a `write` block that
  names the read principal's variables or Entra identity; it cannot detect two variables that
  hold the same login.
- **Opt-in per registration.** A registration opts in with the `--write` launch argument, which
  needs the environment's `write` block. Without it, the write tool refuses every call before it
  connects. A person makes that registration, as section 2 requires of every registration.
- **Five fixed tools.** Section 2's list grows to `query`, `list_objects`, `describe_object`,
  `preview_write` and `write` on every registration, whether or not it opted in, so `tools/list`
  stays the same across calls and does not depend on the opt-in. A registration that did not opt
  in refuses `write` instead of hiding it; #5940's Evidence found hidden tools still callable by
  name.
- **Per-call approval through the tool flag.** `write` carries
  `_meta["anthropic/requiresUserInteraction"]: true`. Claude Code then shows its permission prompt
  on every call, in `acceptEdits`, `auto` and `bypassPermissions` modes too, offers no "don't ask
  again" option, lets no allow rule skip it, and denies the call in `dontAsk` mode. The other four
  tools stay unflagged, so a `dontAsk` or headless session keeps its reads. A client that ignores
  the flag gets no prompt; the opt-in and the write principal's grants still bound it.
- **One guarded batch with a row-count check.** `write` takes one `INSERT`, `UPDATE`, `DELETE` or
  `MERGE` and the number of rows it must affect. The server runs `BEGIN TRANSACTION`, the
  statement, a comparison of `@@ROWCOUNT` with that number, and `COMMIT` or `ROLLBACK` as one
  batch, between the same per-call guards and `@@TRANCOUNT` check as a read. A mismatch rolls back
  and returns a tool error. A write reject list, a heuristic like section 1's, refuses every other
  statement kind, a second statement, transaction control, `OUTPUT` and the `OPENROWSET` family,
  because each could get around the check.
- **No transaction held open across approval.** The person approves before the call reaches the
  server, and the batch opens and ends its transaction within that one call, so no lock is held
  while the prompt waits.
- **A preview of triggers and cascading foreign keys.** #5940's Evidence records that
  `@@ROWCOUNT` sees only the target table, not the rows a trigger or a cascade changes; this
  record has not tested it. `preview_write` lists the triggers on the target, the foreign keys whose
  `ON DELETE` or `ON UPDATE` action cascades from it, and the triggers on each table a cascade
  reaches. It runs as the read principal and lists only what that principal can see.

S4's no-prompt mode, an explicit opt-in for an environment the user deems safe, is not built. It
needs its own amendment.

Sources read on 2026-11-01: [Claude Code MCP, "Require approval for a specific
tool"](https://code.claude.com/docs/en/mcp#require-approval-for-a-specific-tool) and
[@@ROWCOUNT](https://learn.microsoft.com/en-us/sql/t-sql/functions/rowcount-transact-sql) (an
`int`; `BEGIN TRANSACTION` and `COMMIT TRANSACTION` reset it to 0, so the batch reads it straight
after the statement).
