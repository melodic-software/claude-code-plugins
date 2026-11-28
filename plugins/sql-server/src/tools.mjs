import { checkStatement, checkWriteStatement } from './statement.mjs';

/**
 * The executor runs every call against the database. This module never
 * builds SQL for it beyond passing the agent's checked statement through.
 *
 * @typedef {object} Executor
 * @property {(request: { database: string, sql: string }) => Promise<object>} query
 * @property {(request: { database: string, schema?: string }) => Promise<object>} listObjects
 *   Schemas, tables and views.
 * @property {(request: { database: string, schema?: string, name: string }) => Promise<object>} describeObject
 *   Columns, keys and indexes of one table or view.
 * @property {(request: { database: string, schema?: string, name: string }) => Promise<object>} previewWrite
 *   The triggers and cascading foreign keys a write to one table sets off.
 * @property {(request: { database: string, sql: string, expectedRows: number }) => Promise<object>} [write]
 *   One terminated write statement, committed only when it affects expectedRows rows.
 * @property {() => Promise<void>} [close]
 */

export const REQUIRES_USER_INTERACTION = 'anthropic/requiresUserInteraction';

function deepFreeze(value) {
  if (typeof value === 'object' && value !== null) {
    Object.values(value).forEach(deepFreeze);
    Object.freeze(value);
  }
  return value;
}

const nonEmptyString = (description) => ({ type: 'string', minLength: 1, description });

const databaseProperty = nonEmptyString("A database from this registration's allow-list. Defaults to the first one.");
const schemaProperty = nonEmptyString('A schema name, such as dbo.');

export const TOOLS = deepFreeze([
  {
    name: 'query',
    title: 'Run one read query',
    description:
      'Runs one read statement: a single SELECT, optionally led by WITH. Any other statement, a batch, ' +
      'SELECT ... INTO, an OPTION clause, OPENROWSET, OPENQUERY, OPENDATASOURCE and lock-holding table hints are refused. ' +
      'Returns columns, rows, rowCount and truncated: rows stop at the registration row cap (1,000 by default) with truncated true, ' +
      'and a call that runs past the request timeout (30 seconds by default) is cancelled and returns an error.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['sql'],
      properties: {
        sql: nonEmptyString('The SELECT statement to run.'),
        database: databaseProperty,
      },
    },
  },
  {
    name: 'list_objects',
    title: 'List schemas, tables and views',
    description:
      'Lists the schemas, tables and views in one database, or in one schema when schema is given, as far as this ' +
      "registration's read login can see. Returns schemas (names) and objects (schema, name, type), with truncated true " +
      'when a list stopped at the registration row cap. It returns no columns; describe_object gives those.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        database: databaseProperty,
        schema: nonEmptyString('List only objects in this schema.'),
      },
    },
  },
  {
    name: 'describe_object',
    title: 'Describe a table or view',
    description:
      "Describes the columns, keys and indexes of one table or view. Without schema it looks in the login's default schema. " +
      'Returns columns (name, type, maxLength, precision, scale, nullable, default), keys, indexes and truncated; ' +
      "a table or view this registration's read login cannot see is an error.",
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['name'],
      properties: {
        database: databaseProperty,
        schema: schemaProperty,
        name: nonEmptyString('The table or view name.'),
      },
    },
  },
  {
    name: 'preview_write',
    title: 'Preview what a write to a table sets off',
    description:
      'Lists the triggers on one table and the foreign keys whose ON DELETE or ON UPDATE action cascades from it, ' +
      'with the triggers on each table a cascade reaches. Run it before write and show it to the person approving: ' +
      "the write's row-count check counts only the target table's rows. It lists only what this registration's read login can see.",
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['name'],
      properties: {
        database: databaseProperty,
        schema: schemaProperty,
        name: nonEmptyString('The table the write targets.'),
      },
    },
  },
  {
    name: 'write',
    title: 'Run one approved write',
    description:
      'Runs one INSERT, UPDATE, DELETE or MERGE, optionally led by WITH, in one batch that commits only when the ' +
      'statement affects exactly expectedRows rows and rolls back otherwise. A person approves every call. ' +
      'Refused unless this registration was started with --write and a write login. ' +
      'Returns committed and rowCount; a rollback on a row-count mismatch is an error naming both counts. ' +
      'An OUTPUT clause, a batch and SELECT ... INTO are refused. After a timeout, or when a trigger returns more rows than the row cap, ' +
      'whether it committed is not known: read the table before trying again.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['sql', 'expectedRows'],
      properties: {
        sql: nonEmptyString('The write statement to run.'),
        expectedRows: {
          type: 'integer',
          minimum: 0,
          maximum: 2_147_483_647,
          description: 'How many rows of the target table the statement must affect for the batch to commit.',
        },
        database: databaseProperty,
      },
    },
    _meta: { [REQUIRES_USER_INTERACTION]: true },
  },
]);

export const TOOL_NAMES = deepFreeze(TOOLS.map((tool) => tool.name));

export class ToolInputError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ToolInputError';
  }
}

function checkArguments(tool, args) {
  const given = args ?? {};
  if (typeof given !== 'object' || Array.isArray(given)) throw new ToolInputError('arguments must be an object');
  const { properties, required = [] } = tool.inputSchema;
  for (const [key, value] of Object.entries(given)) {
    if (!Object.hasOwn(properties, key)) throw new ToolInputError(`${tool.name} takes no argument named ${key}`);
    const property = properties[key];
    if (property.type === 'integer') {
      if (!Number.isInteger(value) || value < property.minimum || value > property.maximum) {
        throw new ToolInputError(`${key} must be a non-negative integer no larger than ${property.maximum}`);
      }
    } else if (typeof value !== 'string' || value === '') {
      throw new ToolInputError(`${key} must be a non-empty string`);
    }
  }
  for (const key of required) {
    if (!Object.hasOwn(given, key)) throw new ToolInputError(`${tool.name} needs the ${key} argument`);
  }
  return given;
}

export function resolveDatabase(databases, requested) {
  if (requested === undefined) return databases[0];
  if (!databases.includes(requested)) {
    throw new ToolInputError(
      `database ${JSON.stringify(requested)} is not in this registration's allow-list: ${databases.join(', ')}`,
    );
  }
  return requested;
}

const withSchema = (request, schema) => (schema === undefined ? request : { ...request, schema });

export const WRITE_NOT_OPTED_IN =
  'this registration did not opt in to writes: start it with --write and an environment whose write block names a separate write login';

export async function callTool({ databases, executor, writeExecutor }, name, args) {
  const tool = TOOLS.find((candidate) => candidate.name === name);
  if (!tool) throw new ToolInputError(`unknown tool ${name}`);
  if (name === 'write' && !writeExecutor) throw new ToolInputError(WRITE_NOT_OPTED_IN);
  const checked = checkArguments(tool, args);
  const database = resolveDatabase(databases, checked.database);
  switch (name) {
    case 'query': {
      const verdict = checkStatement(checked.sql);
      if (!verdict.ok) throw new ToolInputError(`the reject list refused the statement: ${verdict.reason}`);
      return executor.query({ database, sql: checked.sql });
    }
    case 'write': {
      const verdict = checkWriteStatement(checked.sql);
      if (!verdict.ok) throw new ToolInputError(`the write reject list refused the statement: ${verdict.reason}`);
      const sql = verdict.terminated ? checked.sql : `${checked.sql}\n;`;
      return writeExecutor.write({ database, sql, expectedRows: checked.expectedRows });
    }
    case 'list_objects':
      return executor.listObjects(withSchema({ database }, checked.schema));
    case 'preview_write':
      return executor.previewWrite(withSchema({ database, name: checked.name }, checked.schema));
    default:
      return executor.describeObject(withSchema({ database, name: checked.name }, checked.schema));
  }
}
