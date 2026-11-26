export const USAGE = 'usage: node plugins/sql-server/integration/read-path.mjs [--azure-server <server>.database.windows.net]';

export function parseTarget(argv) {
  if (argv.length === 0) return { kind: 'local' };
  const [flag, server, ...rest] = argv;
  if (flag !== '--azure-server' || rest.length > 0 || !/^[a-z0-9-]+\.database\.windows\.net$/i.test(server ?? '')) {
    throw new Error(USAGE);
  }
  return { kind: 'azure', server };
}

const APP_OBJECTS = [
  'CREATE TABLE dbo.items (id int NOT NULL PRIMARY KEY, name nvarchar(50) NOT NULL);',
  "INSERT INTO dbo.items (id, name) VALUES (1, N'one'), (2, N'two'), (3, N'three');",
  'CREATE SEQUENCE dbo.counter AS int START WITH 1 INCREMENT BY 1;',
  'SELECT NEXT VALUE FOR dbo.counter;',
  'CREATE TRIGGER dbo.items_audit ON dbo.items AFTER INSERT AS SET NOCOUNT ON;',
];

export function fixtureBatches(target, { reader, readerPassword, writer, writerPassword }) {
  const azure = target.kind === 'azure';
  const user = (name, password) => (azure
    ? `CREATE USER [${name}] WITH PASSWORD = N'${password}';`
    : `CREATE USER [${name}] FOR LOGIN [${name}];`);
  const app = [
    ...APP_OBJECTS,
    user(reader, readerPassword),
    `ALTER ROLE db_datareader ADD MEMBER [${reader}];`,
    user(writer, writerPassword),
    `ALTER ROLE db_datareader ADD MEMBER [${writer}];`,
    `ALTER ROLE db_datawriter ADD MEMBER [${writer}];`,
  ];
  if (azure) return app;
  return [
    `CREATE LOGIN [${reader}] WITH PASSWORD = N'${readerPassword}';`,
    `CREATE LOGIN [${writer}] WITH PASSWORD = N'${writerPassword}';`,
    'CREATE DATABASE [app];',
    'CREATE DATABASE [other];',
    'USE [app];',
    ...app,
    'USE [other];',
    'CREATE TABLE dbo.ledger (id int NOT NULL PRIMARY KEY, amount int NOT NULL);',
    'INSERT INTO dbo.ledger (id, amount) VALUES (1, 100);',
    'USE [master];',
  ];
}

export function fingerprintQuery(target) {
  const app = [
    '(SELECT COUNT(*) FROM app.sys.objects WHERE is_ms_shipped = 0) AS appObjects',
    '(SELECT COUNT(*) FROM app.sys.columns AS c JOIN app.sys.objects AS o ON o.object_id = c.object_id WHERE o.is_ms_shipped = 0) AS appColumns',
    '(SELECT COUNT(*) FROM app.dbo.items) AS itemRows',
    '(SELECT CHECKSUM_AGG(CHECKSUM(id, name)) FROM app.dbo.items) AS itemChecksum',
    "(SELECT CAST(current_value AS bigint) FROM app.sys.sequences WHERE name = N'counter') AS counter",
    "(SELECT CAST(is_disabled AS int) FROM app.sys.triggers WHERE name = N'items_audit') AS triggerDisabled",
    '(SELECT COUNT(*) FROM app.sys.database_principals) AS appPrincipals',
    '(SELECT COUNT(*) FROM app.sys.database_role_members) AS appRoleMembers',
    '(SELECT COUNT(*) FROM app.sys.database_permissions) AS appPermissions',
  ];
  const server = [
    '(SELECT COUNT(*) FROM other.sys.objects WHERE is_ms_shipped = 0) AS otherObjects',
    '(SELECT COUNT(*) FROM other.dbo.ledger) AS ledgerRows',
    '(SELECT CHECKSUM_AGG(CHECKSUM(id, amount)) FROM other.dbo.ledger) AS ledgerChecksum',
    '(SELECT COUNT(*) FROM sys.databases) AS databases',
    '(SELECT COUNT(*) FROM sys.server_principals) AS logins',
  ];
  const columns = target.kind === 'azure' ? app : [...app, ...server];
  return `SELECT\n  ${columns.join(',\n  ')};`;
}

export const OUT_OF_SCOPE_REFUSAL = {
  local: { pattern: /not able to access the database/i, by: 'the read-only login' },
  azure: { pattern: /reference to database and\/or server name in .* is not supported/i, by: 'Azure SQL Database, which refuses cross-database names' },
};
