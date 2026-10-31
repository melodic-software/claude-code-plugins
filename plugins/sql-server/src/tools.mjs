// The fixed tool set of ADR 0086 section 2: every registration exposes these
// three tools and no others, and the list never changes while the server runs.
// Each call resolves its database against the registration's allow-list
// before the executor sees it, so a refused name never opens a connection.
import { checkStatement } from './statement.mjs';

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
 * @property {() => Promise<void>} [close]
 */

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
]);

export const TOOL_NAMES = deepFreeze(TOOLS.map((tool) => tool.name));

// A refusal the agent can act on: it reaches the client as a tool error.
export class ToolInputError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ToolInputError';
  }
}

// Every property of every tool is a non-empty string, so the check stays this
// small; a new property of another type needs its own branch here.
function checkArguments(tool, args) {
  const given = args ?? {};
  if (typeof given !== 'object' || Array.isArray(given)) throw new ToolInputError('arguments must be an object');
  const { properties, required = [] } = tool.inputSchema;
  for (const [key, value] of Object.entries(given)) {
    if (!Object.hasOwn(properties, key)) throw new ToolInputError(`${tool.name} takes no argument named ${key}`);
    if (typeof value !== 'string' || value === '') throw new ToolInputError(`${key} must be a non-empty string`);
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

// Checks the call, then hands it to the executor. Throws ToolInputError for a
// refusal; any other error comes from the executor.
export async function callTool({ databases, executor }, name, args) {
  const tool = TOOLS.find((candidate) => candidate.name === name);
  if (!tool) throw new ToolInputError(`unknown tool ${name}`);
  const checked = checkArguments(tool, args);
  const database = resolveDatabase(databases, checked.database);
  switch (name) {
    case 'query': {
      const verdict = checkStatement(checked.sql);
      if (!verdict.ok) throw new ToolInputError(`the reject list refused the statement: ${verdict.reason}`);
      return executor.query({ database, sql: checked.sql });
    }
    case 'list_objects':
      return executor.listObjects(withSchema({ database }, checked.schema));
    default:
      return executor.describeObject(withSchema({ database, name: checked.name }, checked.schema));
  }
}
