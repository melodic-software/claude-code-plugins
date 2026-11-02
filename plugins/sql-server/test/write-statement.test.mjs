import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkWriteStatement } from '../src/statement.mjs';

const accepts = (sql, terminated = false) => assert.deepEqual(checkWriteStatement(sql), { ok: true, terminated }, sql);
const refuses = (sql, reason) => {
  const result = checkWriteStatement(sql);
  assert.equal(result.ok, false, `expected a refusal: ${sql}`);
  assert.match(result.reason, reason, sql);
};

describe('checkWriteStatement accepts', () => {
  it('an INSERT ... VALUES', () => accepts("INSERT INTO dbo.Orders (id, status) VALUES (1, N'new')"));
  it('an INSERT ... SELECT with a set operator', () => accepts('INSERT INTO t (a) SELECT a FROM s UNION ALL SELECT a FROM u'));
  it('an UPDATE with a FROM, a join and a subquery', () =>
    accepts('UPDATE o SET o.status = 2, o.total = (SELECT SUM(x) FROM l) FROM dbo.Orders AS o JOIN c ON c.id = o.cid WHERE o.id = 7'));
  it('a DELETE', () => accepts('DELETE FROM dbo.Orders WHERE id IN (SELECT id FROM stale)'));
  it('a MERGE with its WHEN actions, ending in a semicolon', () =>
    accepts(
      'MERGE INTO t USING (SELECT id, v FROM s) AS src ON t.id = src.id ' +
        'WHEN MATCHED THEN UPDATE SET t.v = src.v WHEN NOT MATCHED THEN INSERT (id, v) VALUES (src.id, src.v) ' +
        'WHEN NOT MATCHED BY SOURCE THEN DELETE;',
      true,
    ));
  it('a write behind a WITH', () => accepts('WITH old AS (SELECT id FROM t WHERE d < 1) DELETE FROM old'));
  it('a table hint', () => accepts('UPDATE t WITH (ROWLOCK) SET a = 1 WHERE id = 2'));
  it('an INSERT TOP (n) INTO ... SELECT', () => accepts('INSERT TOP (5) INTO t (a) SELECT a FROM s'));
  it('reports a trailing semicolon after a comment', () => accepts('DELETE FROM t WHERE id = 1; -- done', true));
  it('a keyword inside a comment or string', () => accepts("UPDATE t SET note = 'COMMIT; EXEC x' /* ROLLBACK */ WHERE id = 1"));
});

describe('checkWriteStatement refuses', () => {
  it('a read', () => refuses('SELECT * FROM t', /only one INSERT, UPDATE, DELETE or MERGE/));
  it('DDL, TRUNCATE and EXEC', () => {
    for (const sql of ['DROP TABLE t', 'CREATE TABLE t (a int)', 'TRUNCATE TABLE t', 'EXEC sp_who']) refuses(sql, /only one INSERT/);
  });
  it('a batch separated by semicolons', () => refuses('DELETE FROM a; DELETE FROM b', /batch of several/));
  it('a second trailing semicolon', () => refuses('DELETE FROM a;;', /batch of several/));
  it('a second write without a semicolon', () => refuses('UPDATE a SET x = 1 DELETE FROM b', /a second DELETE follows the first/));
  it('a MERGE action keyword outside a MERGE', () => refuses('UPDATE a SET x = 1 WHERE 1 = 1 THEN DELETE FROM b', /second DELETE/));
  it('a transaction statement that would end the guarded batch', () => {
    for (const word of ['COMMIT', 'ROLLBACK', 'BEGIN', 'SAVE']) refuses(`DELETE FROM t ${word} TRANSACTION`, new RegExp(`${word} is not allowed`));
  });
  it('a second SET, which marks a session-state statement', () => refuses('UPDATE t SET a = 1 SET NOCOUNT ON', /SET is allowed only in an UPDATE/));
  it('a SET in an INSERT', () => refuses('INSERT INTO t VALUES (1) SET XACT_ABORT OFF', /SET is allowed only/));
  it('a SELECT after an UPDATE, which would take over @@ROWCOUNT', () =>
    refuses('UPDATE t SET a = 1 SELECT * FROM big', /top-level SELECT is allowed only once/));
  it('a second SELECT after INSERT ... SELECT', () => refuses('INSERT INTO t SELECT 1 SELECT 2', /top-level SELECT/));
  it('a SELECT after INSERT ... VALUES or DEFAULT VALUES', () => {
    refuses('INSERT INTO t (a) VALUES (1) SELECT TOP (5) x FROM big', /top-level SELECT/);
    refuses('INSERT INTO t DEFAULT VALUES SELECT 2', /top-level SELECT/);
  });
  it('SELECT ... INTO inside INSERT ... SELECT', () => refuses('INSERT INTO t SELECT x INTO newtab FROM s', /SELECT \.\.\. INTO/));
  it('an unreserved statement starter', () => {
    for (const word of ['DISABLE', 'ENABLE']) refuses(`UPDATE t SET a = 1 ${word} TRIGGER tr ON t`, new RegExp(`${word} is not allowed`));
  });
  it('an INSERT ... EXEC', () => refuses('INSERT INTO t EXEC dbo.p', /EXEC is not allowed/));
  it('an OUTPUT clause', () => refuses('DELETE FROM t OUTPUT deleted.* WHERE id = 1', /OUTPUT clause/));
  it('OPENROWSET', () => refuses("INSERT INTO t SELECT * FROM OPENROWSET('x', 'y', 'z')", /OPENROWSET/));
  it('a WITH that leads no write', () => refuses('WITH c AS (SELECT 1 AS a) SELECT a FROM c', /top-level SELECT/));
  it('a lone WITH', () => refuses('WITH c AS (SELECT 1 AS a)', /a WITH must lead/));
  it('unbalanced parentheses', () => refuses('DELETE FROM t WHERE id IN (1, 2', /unbalanced/));
  it('an empty statement', () => refuses(' ; ', /empty/));
  it('an unterminated string', () => refuses("UPDATE t SET a = 'x", /unterminated string/));
});
