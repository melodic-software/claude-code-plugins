import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { OUT_OF_SCOPE_REFUSAL, USAGE, fingerprintQuery, fixtureBatches, parseTarget } from '../integration/target.mjs';

const AZURE = { kind: 'azure', server: 'example-dev.database.windows.net' };
const PRINCIPALS = { reader: 'r', readerPassword: 'rp', writer: 'w', writerPassword: 'wp' };

describe('parseTarget', () => {
  it('defaults to the local container', () => assert.deepEqual(parseTarget([]), { kind: 'local' }));
  it('takes an Azure logical server', () => assert.deepEqual(parseTarget(['--azure-server', AZURE.server]), AZURE));
  for (const argv of [
    ['--azure-server'],
    ['--azure-server', ''],
    ['--azure-server', 'localhost'],
    ['--azure-server', `${AZURE.server};Password=x`],
    ['--azure-server', AZURE.server, 'extra'],
    ['--server', AZURE.server],
  ]) {
    it(`refuses ${JSON.stringify(argv)}`, () => assert.throws(() => parseTarget(argv), { message: USAGE }));
  }
});

describe('fixtureBatches', () => {
  it('creates contained users in app alone on Azure', () => {
    const sql = fixtureBatches(AZURE, PRINCIPALS).join('\n');
    assert.match(sql, /CREATE USER \[r\] WITH PASSWORD = N'rp';/);
    assert.match(sql, /CREATE USER \[w\] WITH PASSWORD = N'wp';/);
    assert.doesNotMatch(sql, /CREATE LOGIN|CREATE DATABASE|\bUSE\b|ledger/);
  });
  it('creates logins, two databases and login-mapped users locally', () => {
    const sql = fixtureBatches({ kind: 'local' }, PRINCIPALS).join('\n');
    assert.match(sql, /CREATE LOGIN \[r\] WITH PASSWORD = N'rp';/);
    assert.match(sql, /CREATE DATABASE \[other\];/);
    assert.match(sql, /CREATE USER \[r\] FOR LOGIN \[r\];/);
  });
  it('gives the reader db_datareader alone', () => {
    for (const target of [AZURE, { kind: 'local' }]) {
      const grants = fixtureBatches(target, PRINCIPALS).filter((sql) => /MEMBER \[r\]/.test(sql));
      assert.deepEqual(grants, ['ALTER ROLE db_datareader ADD MEMBER [r];']);
    }
  });
});

describe('fingerprintQuery', () => {
  it('reads only app on Azure, which refuses cross-database names', () => {
    assert.doesNotMatch(fingerprintQuery(AZURE), /other\.|sys\.databases|sys\.server_principals/);
    assert.match(fingerprintQuery(AZURE), /AS itemRows/);
  });
  it('also reads the second database and the server locally', () => {
    assert.match(fingerprintQuery({ kind: 'local' }), /other\.dbo\.ledger\) AS ledgerRows/);
  });
});

describe('OUT_OF_SCOPE_REFUSAL', () => {
  it("matches Azure SQL Database's cross-database refusal", () => assert.match(
    "Reference to database and/or server name in 'other.dbo.ledger' is not supported in this version of SQL Server.",
    OUT_OF_SCOPE_REFUSAL.azure.pattern,
  ));
  it("matches the local login's database refusal", () => assert.match(
    'The server principal "mcp_reader" is not able to access the database "other" under the current security context.',
    OUT_OF_SCOPE_REFUSAL.local.pattern,
  ));
});
