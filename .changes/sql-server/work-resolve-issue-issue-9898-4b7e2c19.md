---
bump: minor
---

### Added

- The `setup` skill (`/sql-server:setup check|apply --config <path>`). `check` runs `skills/setup/scripts/check-setup.mjs`, which prints a PASS, FAIL or INFO row for Node.js, the config against `config.v1.schema.json`, each environment, each credential variable (set or not, never its value) and the server copy in the plugin data directory, then a `claude mcp add` command per environment that names each credential as `--env 'NAME=${NAME}'`. It exits 1 on a FAIL row, such as a config with a literal password. With an environment already registered, `check` also lists the principal's database permissions through its `query` tool. `apply` copies the server into the plugin data directory and runs `npm ci` there, then runs each registration command at user scope once the user confirms; project scope is refused ([#9898](https://github.com/melodic-software/claude-code-plugins/issues/9898)).
- `reference/azure-sql-database.md`: a free Azure SQL Database for a trial (`--use-free-limit true --free-limit-exhaustion-behavior AutoPause`), a read-only Entra contained user in `db_datareader`, the config entry, and what differs from a local SQL Server, `READ_COMMITTED_SNAPSHOT` being on by default there.
- The README's Setup section and a list of the limits of each guarantee, from ADR 0086 and the read-safety measurement.
