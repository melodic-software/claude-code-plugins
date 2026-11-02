// Runs every call on SQL Server through tedious, per ADR 0086 sections 1 and 4
// and its write-tier amendment. The plugin owns the pool, so the guards and
// the discard rule live here: a call takes a connection, runs the guard batch, runs its statements
// (a read in autocommit, a write in its own one-batch transaction), checks
// @@TRANCOUNT, and hands the connection back only when all of that ended
// cleanly. A timeout, a cancel, an error or an open transaction closes it.

export const APP_NAME = 'sql-server-plugin (agent session)';

// The row chosen in reference/read-safety-measurement.md; test/defaults.test.mjs
// holds them to it.
export const DEFAULT_LIMITS = Object.freeze({ requestTimeoutMs: 30_000, lockTimeoutMs: 5_000, rowCap: 1_000 });
export const POOL_MAX = 2;
export const IDLE_TIMEOUT_MS = 30_000;

export const TRANCOUNT_CHECK = 'SELECT @@TRANCOUNT AS trancount;';

// Runs through execSqlBatch, not execSql: a SET inside sp_executesql reverts
// when that batch returns, so the settings would not reach the statement.
export function guardBatch(lockTimeoutMs) {
  if (!Number.isInteger(lockTimeoutMs) || lockTimeoutMs < -1) throw new Error(`lockTimeoutMs must be an integer, not ${lockTimeoutMs}`);
  return [
    'IF @@TRANCOUNT > 0 ROLLBACK;',
    'SET IMPLICIT_TRANSACTIONS OFF;',
    'SET XACT_ABORT ON;',
    'SET TRANSACTION ISOLATION LEVEL READ COMMITTED;',
    `SET LOCK_TIMEOUT ${lockTimeoutMs};`,
  ].join('\n');
}

const LIST_SCHEMAS = `SELECT SCHEMA_NAME AS [schema]
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE @schema IS NULL OR SCHEMA_NAME = @schema
ORDER BY SCHEMA_NAME;`;

const LIST_OBJECTS = `SELECT TABLE_SCHEMA AS [schema], TABLE_NAME AS [name], TABLE_TYPE AS [type]
FROM INFORMATION_SCHEMA.TABLES
WHERE @schema IS NULL OR TABLE_SCHEMA = @schema
ORDER BY TABLE_SCHEMA, TABLE_NAME;`;

const OBJECT_SCHEMA = 'COALESCE(@schema, SCHEMA_NAME())';

const DESCRIBE_COLUMNS = `SELECT COLUMN_NAME AS [name], DATA_TYPE AS [type], CHARACTER_MAXIMUM_LENGTH AS [maxLength],
  NUMERIC_PRECISION AS [precision], NUMERIC_SCALE AS [scale], IS_NULLABLE AS [nullable], COLUMN_DEFAULT AS [default]
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = ${OBJECT_SCHEMA} AND TABLE_NAME = @name
ORDER BY ORDINAL_POSITION;`;

const DESCRIBE_KEYS = `SELECT tc.CONSTRAINT_NAME AS [name], tc.CONSTRAINT_TYPE AS [type], kcu.COLUMN_NAME AS [column]
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE AS kcu
  ON kcu.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA AND kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
WHERE tc.TABLE_SCHEMA = ${OBJECT_SCHEMA} AND tc.TABLE_NAME = @name
ORDER BY tc.CONSTRAINT_NAME, kcu.ORDINAL_POSITION;`;

const DESCRIBE_INDEXES = `SELECT i.name AS [name], i.type_desc AS [type], i.is_unique AS [unique], c.name AS [column],
  ic.is_included_column AS [included]
FROM sys.indexes AS i
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID(QUOTENAME(${OBJECT_SCHEMA}) + N'.' + QUOTENAME(@name))
ORDER BY i.name, ic.is_included_column, ic.key_ordinal, ic.index_column_id;`;

// The tables a write to the target reaches: the target at depth 0, then each
// table whose foreign key has a cascading action into one already reached.
// SQL Server refuses a cascade cycle, and the depth bound keeps this finite anyway.
const CASCADE_REACH = `WITH reached AS (
  SELECT t.object_id AS object_id, CAST(NULL AS int) AS fk_id, 0 AS depth
  FROM sys.tables AS t
  WHERE t.object_id = OBJECT_ID(QUOTENAME(${OBJECT_SCHEMA}) + N'.' + QUOTENAME(@name))
  UNION ALL
  SELECT fk.parent_object_id, fk.object_id, r.depth + 1
  FROM reached AS r
  JOIN sys.foreign_keys AS fk ON fk.referenced_object_id = r.object_id
  WHERE (fk.delete_referential_action <> 0 OR fk.update_referential_action <> 0) AND r.depth < 32
)`;

const PREVIEW_CASCADES = `${CASCADE_REACH}
SELECT r.depth AS [depth], OBJECT_SCHEMA_NAME(r.object_id) + N'.' + OBJECT_NAME(r.object_id) AS [table],
  fk.name AS [foreignKey], OBJECT_SCHEMA_NAME(fk.referenced_object_id) + N'.' + OBJECT_NAME(fk.referenced_object_id) AS [references],
  fk.delete_referential_action_desc AS [onDelete], fk.update_referential_action_desc AS [onUpdate]
FROM reached AS r
LEFT JOIN sys.foreign_keys AS fk ON fk.object_id = r.fk_id
ORDER BY r.depth, [table], [foreignKey];`;

// One row per trigger and event it fires on.
const PREVIEW_TRIGGERS = `${CASCADE_REACH}
SELECT OBJECT_SCHEMA_NAME(tr.parent_id) + N'.' + OBJECT_NAME(tr.parent_id) AS [table], tr.name AS [name],
  te.type_desc AS [event], tr.is_instead_of_trigger AS [insteadOf], tr.is_disabled AS [disabled]
FROM sys.triggers AS tr
JOIN sys.trigger_events AS te ON te.object_id = tr.object_id
WHERE tr.parent_id IN (SELECT object_id FROM reached)
ORDER BY [table], [name], [event];`;

// @@ROWCOUNT is an int.
const MAX_INT = 2_147_483_647;

// One batch holds the transaction from BEGIN to COMMIT or ROLLBACK, so no
// transaction stays open between calls or across the person's approval.
// BEGIN and COMMIT reset @@ROWCOUNT, so it is read straight after the
// statement. statement must already end in a semicolon.
export function writeBatch(statement, expectedRows) {
  if (!Number.isInteger(expectedRows) || expectedRows < 0 || expectedRows > MAX_INT) {
    throw new Error(`expectedRows must be a non-negative integer no larger than ${MAX_INT}, not ${expectedRows}`);
  }
  return [
    'DECLARE @affected int;',
    'BEGIN TRANSACTION;',
    statement,
    'SET @affected = @@ROWCOUNT;',
    `IF @affected = ${expectedRows}`,
    'BEGIN COMMIT TRANSACTION; SELECT CAST(1 AS bit) AS [committed], @affected AS [affected]; END',
    'ELSE',
    'BEGIN ROLLBACK TRANSACTION; SELECT CAST(0 AS bit) AS [committed], @affected AS [affected]; END',
  ].join('\n');
}

function readSecret(env, name) {
  const value = env[name];
  if (typeof value !== 'string' || value === '') throw new Error(`the environment variable ${name} is not set`);
  return value;
}

async function loadTedious() {
  try {
    const module = await import('tedious');
    return module.default ?? module;
  } catch (error) {
    throw new Error(`cannot load the tedious driver; install the plugin's dependencies: ${error.message}`);
  }
}

async function defaultAzureCredential(clientId) {
  let identity;
  try {
    identity = await import('@azure/identity');
  } catch (error) {
    throw new Error(`cannot load @azure/identity; install the plugin's dependencies: ${error.message}`);
  }
  return new identity.DefaultAzureCredential(clientId === undefined ? undefined : { managedIdentityClientId: clientId });
}

// tedious returns binary columns as Buffers; hex keeps them readable in JSON.
const toJson = (value) => {
  if (Buffer.isBuffer(value)) return `0x${value.toString('hex')}`;
  if (typeof value === 'bigint') return value.toString();
  return value;
};

const toObjects = ({ columns, rows }) => rows.map((row) => Object.fromEntries(columns.map((column, i) => [column, row[i]])));

/**
 * @param {ReturnType<typeof import('./registration.mjs').bindRegistration>} registration
 * @param {object} [options]
 * @param {{ Connection: Function, Request: Function, TYPES: object }} [options.driver] tedious, or a fake; loaded on first connect when omitted.
 * @param {(clientId?: string) => object | Promise<object>} [options.createCredential] The TokenCredential for entra-default.
 * @param {Record<string, string | undefined>} [options.env] Where sql-login reads its named variables.
 * @returns {import('./tools.mjs').Executor}
 */
export function createTediousExecutor(
  registration,
  { driver, createCredential = defaultAzureCredential, env = process.env, maxConnections = POOL_MAX, idleTimeoutMs = IDLE_TIMEOUT_MS } = {},
) {
  const limits = { ...DEFAULT_LIMITS, ...registration.limits };
  let driverReady = driver ? Promise.resolve(driver) : undefined;
  let credential;
  const idle = [];
  const waiters = [];
  const broken = new WeakSet();
  let open = 0;
  let closed = false;

  // A failed load is not kept, so installing the dependencies or a credential
  // that comes back later takes effect on the next call.
  const getDriver = () => {
    driverReady ??= loadTedious().catch((error) => {
      driverReady = undefined;
      throw error;
    });
    return driverReady;
  };

  async function authentication() {
    const { auth } = registration;
    if (auth.type === 'sql-login') {
      return { type: 'default', options: { userName: readSecret(env, auth.user.env), password: readSecret(env, auth.password.env) } };
    }
    credential ??= Promise.resolve()
      .then(() => createCredential(auth.clientId))
      .catch((error) => {
        credential = undefined;
        throw error;
      });
    return { type: 'token-credential', options: { credential: await credential } };
  }

  // tedious takes a named instance (host\INSTANCE) as instanceName, which
  // excludes a port.
  const [host, instanceName] = registration.server.split('\\');
  const endpoint =
    instanceName === undefined ? (registration.port === undefined ? {} : { port: registration.port }) : { instanceName };

  async function connect(database) {
    const { Connection } = await getDriver();
    const config = {
      server: host,
      authentication: await authentication(),
      options: {
        database,
        appName: APP_NAME,
        encrypt: true,
        // The executor's own timer cancels a call; see run().
        requestTimeout: 0,
        enableImplicitTransactions: false,
        abortTransactionOnError: true,
        rowCollectionOnRequestCompletion: false,
        useColumnNames: false,
        ...endpoint,
      },
    };
    const connection = new Connection(config);
    connection.on('error', () => broken.add(connection));
    connection.on('end', () => broken.add(connection));
    await new Promise((resolve, reject) => {
      connection.connect((error) => (error ? reject(error) : resolve()));
    });
    return connection;
  }

  const wake = () => waiters.shift()?.();

  function discard(entry) {
    clearTimeout(entry.timer);
    open -= 1;
    try {
      entry.connection.close();
    } finally {
      wake();
    }
  }

  function release(entry) {
    if (closed || broken.has(entry.connection)) {
      discard(entry);
      return;
    }
    entry.timer = setTimeout(() => {
      idle.splice(idle.indexOf(entry), 1);
      discard(entry);
    }, idleTimeoutMs);
    entry.timer.unref?.();
    idle.push(entry);
    wake();
  }

  async function acquire(database) {
    for (;;) {
      if (closed) throw new Error('the executor is closed');
      // The server can end an idle session; such a connection is never handed out.
      for (const entry of idle.filter((candidate) => broken.has(candidate.connection))) {
        idle.splice(idle.indexOf(entry), 1);
        discard(entry);
      }
      const reusable = idle.findIndex((entry) => entry.database === database);
      if (reusable >= 0) {
        const [entry] = idle.splice(reusable, 1);
        clearTimeout(entry.timer);
        return entry;
      }
      // A full pool with an idle connection to another database gives up that one.
      if (open >= maxConnections && idle.length > 0) discard(idle.shift());
      if (open < maxConnections) {
        open += 1;
        try {
          return { database, connection: await connect(database) };
        } catch (error) {
          open -= 1;
          wake();
          throw error;
        }
      }
      await new Promise((resolve) => waiters.push(resolve));
    }
  }

  function execute(connection, { Request, TYPES }, sql, { batch = false, params = {}, onColumns, onRow } = {}) {
    return new Promise((resolve, reject) => {
      const request = new Request(sql, (error) => (error ? reject(error) : resolve()));
      for (const [name, value] of Object.entries(params)) request.addParameter(name, TYPES.NVarChar, value ?? null);
      if (onColumns) request.on('columnMetadata', onColumns);
      if (onRow) request.on('row', onRow);
      if (batch) connection.execSqlBatch(request);
      else connection.execSql(request);
    });
  }

  // Runs statements one after another on one connection between the guard
  // batch and the transaction check, all under one request timeout. Each
  // result set stops at the row cap: the row past it cancels the request.
  async function run(database, statements) {
    const tedious = await getDriver();
    const entry = await acquire(database);
    const { connection } = entry;
    let timedOut = false;
    let capped = false;
    let reusable = false;
    const timer = setTimeout(() => {
      // A cancel the row cap sent is already on its way.
      if (capped) return;
      timedOut = true;
      connection.cancel();
    }, limits.requestTimeoutMs);
    try {
      await execute(connection, tedious, guardBatch(limits.lockTimeoutMs), { batch: true });
      const results = [];
      for (const { sql, params } of statements) {
        const result = { columns: [], rows: [], truncated: false };
        results.push(result);
        try {
          await execute(connection, tedious, sql, {
            params,
            onColumns: (columns) => {
              result.columns = columns.map((column) => column.colName);
            },
            onRow: (row) => {
              if (result.truncated) return;
              if (result.rows.length >= limits.rowCap) {
                result.truncated = true;
                capped = true;
                connection.cancel();
                return;
              }
              result.rows.push(row.map((column) => toJson(column.value)));
            },
          });
        } catch (error) {
          if (!(result.truncated && !timedOut && error?.code === 'ECANCEL')) throw error;
        }
        if (result.truncated) return results;
      }
      let trancount;
      await execute(connection, tedious, TRANCOUNT_CHECK, {
        batch: true,
        onRow: (row) => {
          trancount = row[0]?.value;
        },
      });
      // A cancel sent as the request finished can still reach the next one.
      reusable = trancount === 0 && !timedOut;
      return results;
    } catch (error) {
      if (timedOut) {
        throw Object.assign(new Error(`the call ran past the ${limits.requestTimeoutMs} ms request timeout and was cancelled`), { timedOut: true });
      }
      throw error;
    } finally {
      clearTimeout(timer);
      if (reusable) release(entry);
      else discard(entry);
    }
  }

  return {
    async query({ database, sql }) {
      const [result] = await run(database, [{ sql }]);
      return { columns: result.columns, rows: result.rows, rowCount: result.rows.length, truncated: result.truncated };
    },

    async listObjects({ database, schema }) {
      const params = { schema };
      const [schemas, objects = { columns: [], rows: [], truncated: false }] = await run(database, [
        { sql: LIST_SCHEMAS, params },
        { sql: LIST_OBJECTS, params },
      ]);
      return {
        schemas: toObjects(schemas).map((row) => row.schema),
        objects: toObjects(objects),
        truncated: schemas.truncated || objects.truncated,
      };
    },

    async describeObject({ database, schema, name }) {
      const params = { schema, name };
      const sets = await run(database, [
        { sql: DESCRIBE_COLUMNS, params },
        { sql: DESCRIBE_KEYS, params },
        { sql: DESCRIBE_INDEXES, params },
      ]);
      const [columns, keys, indexes] = [0, 1, 2].map((i) => sets[i] ?? { columns: [], rows: [], truncated: false });
      if (columns.rows.length === 0) {
        throw new Error(`${database} has no table or view named ${schema === undefined ? name : `${schema}.${name}`} that this login can see`);
      }
      return {
        columns: toObjects(columns),
        keys: toObjects(keys),
        indexes: toObjects(indexes),
        truncated: sets.some((set) => set.truncated),
      };
    },

    async previewWrite({ database, schema, name }) {
      const params = { schema, name };
      const sets = await run(database, [
        { sql: PREVIEW_CASCADES, params },
        { sql: PREVIEW_TRIGGERS, params },
      ]);
      const [reached, triggers] = [0, 1].map((i) => sets[i] ?? { columns: [], rows: [], truncated: false });
      const tables = toObjects(reached);
      const target = tables.find((row) => row.depth === 0);
      if (target === undefined) {
        throw new Error(`${database} has no table named ${schema === undefined ? name : `${schema}.${name}`} that this login can see`);
      }
      return {
        table: target.table,
        cascades: tables.filter((row) => row.depth > 0),
        triggers: toObjects(triggers),
        truncated: sets.some((set) => set.truncated),
      };
    },

    // Throws when the batch rolled back, so a mismatch reaches the agent as a tool error.
    async write({ database, sql, expectedRows }) {
      const unknown = 'whether it committed is not known; read the table before trying again';
      let result;
      try {
        [result] = await run(database, [{ sql: writeBatch(sql, expectedRows) }]);
      } catch (error) {
        // The cancel can land after COMMIT, while the verdict is on its way.
        if (error.timedOut) throw new Error(`${error.message}, so ${unknown}`);
        throw error;
      }
      // A trigger can return rows of its own before the verdict; the verdict is the last row.
      const verdict = result.truncated ? undefined : result.rows.at(-1);
      if (verdict === undefined || verdict.length !== 2) throw new Error(`the write batch returned no verdict, so ${unknown}`);
      const [committed, affected] = verdict;
      if (!committed) {
        throw new Error(`rolled back: the statement affected ${affected} rows, not the expected ${expectedRows}`);
      }
      return { committed: true, rowCount: affected };
    },

    async close() {
      closed = true;
      for (const entry of idle.splice(0)) discard(entry);
      for (const waiter of waiters.splice(0)) waiter();
    },
  };
}
