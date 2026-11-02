// The fixed tool set of ADR 0086 section 2 and its write-tier amendment: every
// registration exposes these five tools and no others, and the list never
// changes while the server runs. The write tool is listed on every registration and refused on one that
// did not opt in. Each call resolves its database against the registration's
// allow-list before the executor sees it, so a refused name never opens a
// connection.
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

// Claude Code shows the permission prompt for a tool carrying this on every
// call, in every permission mode, and an allow rule does not skip it.
export const REQUIRES_USER_INTERACTION = 'anthropic/requiresUserInteraction';

function deepFreeze(value) {
  if (typeof value === 'object' && value !== null) {
    Object.values(value).forEach(deepFreeze);
    Object.freeze(value);
  }
  return value;
}

const databaseProperty = {
  type: 'string',
  minLength: 1,
  description: "A database from this registration's allow-list. Defaults to the first one.",
};

const schemaProperty = {
  type: 'string',
  minLength: 1,
  description: 'A schema name, such as dbo.',
};

export const TOOLS = deepFreeze([
  {
    name: 'query',
    title: 'Run one read query',
    description:
      'Runs one read statement: a single SELECT, optionally led by WITH. Any other statement, a batch, ' +
      'SELECT ... INTO, an OPTION clause, OPENROWSET, OPENQUERY, OPENDATASOURCE and lock-holding table hints are refused.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['sql'],
      properties: {
        sql: { type: 'string', minLength: 1, description: 'The SELECT statement to run.' },
        database: databaseProperty,
      },
    },
  },
  {
    name: 'list_objects',
    title: 'List schemas, tables and views',
    description: 'Lists the schemas, tables and views in one database.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        database: databaseProperty,
        schema: { ...schemaProperty, description: 'List only objects in this schema.' },
      },
    },
  },
  {
    name: 'describe_object',
    title: 'Describe a table or view',
    description: 'Describes the columns, keys and indexes of one table or view.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['name'],
      properties: {
        database: databaseProperty,
        schema: schemaProperty,
        name: { type: 'string', minLength: 1, description: 'The table or view name.' },
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
        name: { type: 'string', minLength: 1, description: 'The table the write targets.' },
      },
    },
  },
  {
    name: 'write',
    title: 'Run one approved write',
    description:
      'Runs one INSERT, UPDATE, DELETE or MERGE, optionally led by WITH, in one batch that commits only when the ' +
      'statement affects exactly expectedRows rows and rolls back otherwise. A person approves every call. ' +
      'Refused unless this registration was started with --write and a write login.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['sql', 'expectedRows'],
      properties: {
        sql: { type: 'string', minLength: 1, description: 'The write statement to run.' },
        expectedRows: {
          type: 'integer',
          minimum: 0,
          // @@ROWCOUNT is an int.
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

// A refusal the agent can act on: it reaches the client as a tool error.
export class ToolInputError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ToolInputError';
  }
}

// Every property of every tool is a non-empty string or a bounded
// non-negative integer, so the check stays this small; a property of another
// type needs its own branch here.
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

// Checks the call, then hands it to the executor. Throws ToolInputError for a
// refusal; any other error comes from the executor. writeExecutor, which
// connects as the write principal, exists only on a registration that opted in.
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
      // The executor runs more statements after this one, and MERGE must end in a semicolon.
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
