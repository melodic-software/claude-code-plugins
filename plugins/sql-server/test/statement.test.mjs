import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkStatement, LOCK_HINTS, tokenize } from '../src/statement.mjs';

const accepts = (sql) => assert.deepEqual(checkStatement(sql), { ok: true }, sql);
const refuses = (sql, reason) => {
  const result = checkStatement(sql);
  assert.equal(result.ok, false, `expected a refusal: ${sql}`);
  assert.match(result.reason, reason, sql);
};

describe('checkStatement accepts', () => {
  it('a SELECT', () => accepts('SELECT id, name FROM dbo.Customers WHERE id = 1'));
  it('a SELECT with one trailing semicolon', () => accepts('select top 10 * from dbo.Orders;'));
  it('a WITH query', () =>
    accepts('WITH recent AS (SELECT id FROM dbo.Orders WHERE placed > @since), big AS (SELECT 1 AS n) SELECT * FROM recent'));
  it('UNION ALL, EXCEPT and INTERSECT', () =>
    accepts('SELECT 1 UNION ALL SELECT 2 EXCEPT SELECT 3 INTERSECT SELECT 1'));
  it('a subquery and OFFSET ... FETCH', () =>
    accepts('SELECT * FROM (SELECT id FROM t) d ORDER BY id OFFSET 10 ROWS FETCH NEXT 5 ROWS ONLY'));
  it('a NOLOCK table hint', () => accepts('SELECT * FROM dbo.Orders WITH (NOLOCK)'));
  it('a variable named like a keyword', () => accepts('SELECT @update AS x'));
});

describe('a keyword that does not count', () => {
  it('inside a line comment', () => accepts('SELECT 1 -- DELETE FROM dbo.Orders; DROP TABLE x\n'));
  it('inside a nested block comment', () => accepts('SELECT /* INTO /* UPDATE */ OPENROWSET */ 1'));
  it('inside a string literal', () => accepts("SELECT 'DELETE FROM t; EXEC x' AS a, N'it''s INTO' AS b"));
  it('inside a bracketed identifier', () => accepts('SELECT [INTO], [UPDLOCK], [x]]; DROP] FROM [OPENQUERY]'));
  it('inside a quoted identifier', () => accepts('SELECT "INTO" FROM "EXECUTE"'));
});

describe('checkStatement refuses', () => {
  it('a write statement', () => refuses("UPDATE dbo.Customers SET name = 'x'", /only a SELECT/));
  it('INSERT, DELETE, MERGE and TRUNCATE', () => {
    for (const sql of ['INSERT INTO t VALUES (1)', 'DELETE FROM t', 'MERGE t USING s ON 1=1', 'TRUNCATE TABLE t']) {
      refuses(sql, /only a SELECT/);
    }
  });
  it('a write behind a WITH', () => refuses('WITH x AS (SELECT 1 AS a) DELETE FROM x', /DELETE is not allowed/));
  it('USE', () => refuses('USE master', /only a SELECT/));
  it('EXECUTE AS', () => refuses("EXECUTE AS USER = 'dbo'", /only a SELECT/));
  it('EXECUTE AS after a SELECT', () => refuses("SELECT 1 EXECUTE AS LOGIN = 'sa'", /EXECUTE is not allowed/));
  it('SELECT ... INTO', () => refuses('SELECT * INTO dbo.Copy FROM dbo.Customers', /INTO writes a table/));
  it('a multi-statement batch split by semicolons', () => refuses('SELECT 1; SELECT 2', /only one statement/));
  it('a multi-statement batch with no semicolon', () => refuses('SELECT 1 SELECT 2', /a second SELECT/));
  it('a write appended with no semicolon', () => refuses('SELECT 1 DROP TABLE dbo.Orders', /DROP is not allowed/));
  it('a write after a line comment ended by a lone carriage return', () =>
    refuses('SELECT 1 -- note\rDROP TABLE dbo.Orders', /DROP is not allowed/));
  it('ADD appended with no semicolon', () =>
    refuses('SELECT 1 ADD SIGNATURE TO dbo.p BY CERTIFICATE c', /ADD is not allowed/));
  it('SET and WAITFOR appended', () => {
    refuses('SELECT 1 SET LOCK_TIMEOUT -1', /SET is not allowed/);
    refuses("SELECT 1 WAITFOR DELAY '00:01'", /WAITFOR is not allowed/);
  });
  it('a user OPTION (...)', () => refuses('SELECT * FROM t OPTION (MAXDOP 1)', /OPTION/));
  it('OPENROWSET', () => refuses("SELECT * FROM OPENROWSET('SQLNCLI', 'x', 'SELECT 1')", /OPENROWSET/));
  it('OPENQUERY', () => refuses("SELECT * FROM OPENQUERY(linked, 'SELECT 1')", /OPENQUERY/));
  it('OPENDATASOURCE', () =>
    refuses("SELECT * FROM OPENDATASOURCE('SQLNCLI', 'x').db.dbo.t", /OPENDATASOURCE/));
  for (const hint of LOCK_HINTS) {
    it(`the ${hint} lock hint`, () => refuses(`SELECT * FROM dbo.Orders WITH (${hint.toLowerCase()})`, new RegExp(hint)));
  }
  it('a cursor FETCH', () => refuses('SELECT 1 FETCH NEXT FROM c', /FETCH/));
  it('an empty or comment-only text', () => {
    refuses('', /empty/);
    refuses(' ; -- SELECT 1', /empty/);
  });
  it('a WITH with no main SELECT', () => refuses('WITH x AS (SELECT 1 AS a)', /must lead a SELECT/));
  it('an unterminated string, comment or identifier', () => {
    refuses("SELECT 'abc", /unterminated string/);
    refuses('SELECT 1 /* DROP', /unterminated/);
    refuses('SELECT [abc', /unterminated identifier/);
  });
  it('unbalanced parentheses', () => refuses('SELECT (1', /unbalanced/));
  it('a leading parenthesis', () => refuses('(SELECT 1)', /only a SELECT/));
});

describe('tokenize', () => {
  it('drops comments and keeps literals and identifiers as single tokens', () => {
    assert.deepEqual(tokenize("SELECT [a b], 'c''d' -- x\n/* y */ FROM t"), [
      { kind: 'word', value: 'SELECT' },
      { kind: 'ident', value: 'a b' },
      { kind: 'punct', value: ',' },
      { kind: 'string', value: "c'd" },
      { kind: 'word', value: 'FROM' },
      { kind: 'word', value: 'T' },
    ]);
  });
});
