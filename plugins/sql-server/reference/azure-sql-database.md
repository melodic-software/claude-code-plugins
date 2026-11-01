# Azure SQL Database

Azure SQL Database needs no code of its own: an environment in the config with an `entra-default`
or `sql-login` `auth` block reaches it. This page covers a free database for a trial, a read-only
Entra principal, the config entry and what differs from a local SQL Server.

## A free database for a trial

Each Azure subscription can hold up to 10 free General Purpose databases. Each gets 100,000 vCore
seconds, 32 GB of data and 32 GB of backup storage per month. `--use-free-limit true` makes the
database free; without it the command creates a billable serverless database.
`--free-limit-exhaustion-behavior AutoPause` pauses the database once the month's free limit runs
out, so it stops charges until the allowance resets at the start of the next month. The other
behavior, `BillOverUsage`, keeps the database online and bills the overage, and a database cannot
switch back from it.

```bash
az sql db create --name <database-name> --server <server-name> --resource-group <resource-group> --edition GeneralPurpose --family Gen5 --capacity 2 --compute-model Serverless --use-free-limit true --free-limit-exhaustion-behavior AutoPause
az sql server firewall-rule create --name AllowClientIp --server <server-name> --resource-group <resource-group> --start-ip-address <client-ip-address> --end-ip-address <client-ip-address>
```

The second command lets your machine's public IP address through the logical server's firewall.
A free database pauses after 15 minutes without activity, and an open connection keeps it awake.
The server's pool closes a connection idle for 30 seconds, so a registration left running does not
hold the database awake between calls.

## A read-only Entra principal

The read-only principal is the guarantee here as on any server: a registration on an identity that
can write is not read-only, whatever the reject list does.

1. Set a Microsoft Entra admin on the logical server (portal: the server's **Microsoft Entra ID**
   page, **Set admin**; CLI: `az sql server ad-admin create`). Done when the admin's name shows in
   the **Microsoft Entra admin** field.
2. Connect to the database the agent reads as an Entra identity with `ALTER ANY USER`, such as that
   admin, and create a contained user that holds read access only:

   ```sql
   CREATE USER [reader@contoso.com] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [reader@contoso.com];
   ```

   For a managed identity or service principal, use its display name in the brackets. Grant
   nothing else: `db_datareader` reads every user table and view in that database, and a contained
   user exists only in the database it was created in. Done when
   `SELECT name FROM sys.database_principals WHERE name = 'reader@contoso.com'` returns one row.
3. Repeat step 2 in each other database the environment lists, and in no database it does not.

## The config entry

```json
{
  "schemaVersion": 1,
  "environments": {
    "azure-dev": {
      "server": "example-dev.database.windows.net",
      "databases": ["app"],
      "auth": { "type": "entra-default" }
    }
  }
}
```

- `server` is the logical server name from the database's **Overview** page in the portal. Leave
  out `port`: clients reach the gateway on 1433, the default. From inside Azure the default
  connection policy is Redirect, which also needs outbound ports 11000 to 11999.
- `entra-default` signs in with `DefaultAzureCredential`, which tries, in order, environment
  variables, workload identity, managed identity, Visual Studio Code, the Azure CLI, Azure
  PowerShell and the Azure Developer CLI. On a workstation, `az login` as the reader identity is
  enough. Set `clientId` to pick a user-assigned managed identity.
- A `sql-login` entry works too, with a contained SQL user that is a member of `db_datareader`
  only. Entra is the better choice: the config then names no password variable at all.

Check the file with `/sql-server:setup check`, or from a checkout of this repository:

```bash
node plugins/sql-server/skills/setup/scripts/check-setup.mjs --config ~/.config/sql-server/config.json
```

## What differs from a local SQL Server

- **Reads do not block writers.** `READ_COMMITTED_SNAPSHOT` is on by default in Azure SQL Database
  and off in SQL Server. With it on, the server's pinned `READ COMMITTED` reads row versions
  instead of taking shared locks. The [measurement](read-safety-measurement.md) ran with it off,
  so its lock-wait rows show the local container's case.
- **Entra token lifetime.** `tedious` asks the credential for a token on each connect, and the
  pool closes idle connections. Whether a connection that stays busy past its token's expiry keeps
  working is not verified.
- **Not tested here.** The integration test runs against a local container only; no test in this
  plugin connects to Azure SQL Database.

Sources read on 2026-11-01:
[Azure SQL Database free tier](https://learn.microsoft.com/en-us/azure/azure-sql/database/free-tier),
[Configure Microsoft Entra authentication](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-configure),
[Database-level roles](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/database-level-roles),
[Connectivity architecture](https://learn.microsoft.com/en-us/azure/azure-sql/database/connectivity-architecture),
[Transaction locking and row versioning guide](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
and [DefaultAzureCredential](https://learn.microsoft.com/en-us/javascript/api/@azure/identity/defaultazurecredential).
