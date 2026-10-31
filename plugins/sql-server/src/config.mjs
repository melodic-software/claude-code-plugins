// Loads the one config file a registration names with --config, per ADR 0086
// section 5: the file sits outside the project directory, carries a known
// schemaVersion, holds no literal credential and matches the published schema.
import { readFileSync, realpathSync } from 'node:fs';
import { isAbsolute, relative, sep } from 'node:path';
import { compileSchema } from './schema-validate.mjs';

export const SCHEMA_VERSION = 1;

const validateV1 = compileSchema(
  JSON.parse(readFileSync(new URL('../schemas/config.v1.schema.json', import.meta.url), 'utf8')),
);

export class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ConfigError';
  }
}

const PASSWORD_KEY = /^(password|passwd|pwd)$/i;
const CONNECTION_STRING_KEY = /^(connection_?string|conn_?str)$/i;
const PASSWORD_PAIR = /(^|[;\s])(password|passwd|pwd)\s*=/i;
const CONNECTION_STRING_PAIR =
  /(^|;)\s*(server|data source|addr|address|network address|initial catalog|database|user id|uid|authentication)\s*=/i;
const CONNECTION_URL = /^(jdbc:)?(sqlserver|mssql):\/\//i;

function isInside(child, dir) {
  const rel = relative(dir, child);
  return rel === '' || (rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
}

// Throws on the first literal credential found. The message names where it
// sits, never the value.
function refuseLiterals(node, path) {
  if (Array.isArray(node)) {
    node.forEach((item, i) => refuseLiterals(item, `${path}/${i}`));
    return;
  }
  if (typeof node === 'string') {
    if (PASSWORD_PAIR.test(node)) throw new ConfigError(`${path}: holds a literal password; name an environment variable instead`);
    if (CONNECTION_STRING_PAIR.test(node) || CONNECTION_URL.test(node)) {
      throw new ConfigError(`${path}: holds a literal connection string; give server, port and databases as separate properties`);
    }
    return;
  }
  if (typeof node !== 'object' || node === null) return;
  for (const [key, value] of Object.entries(node)) {
    const at = `${path}/${key}`;
    if (PASSWORD_KEY.test(key) && (typeof value !== 'object' || value === null || Array.isArray(value))) {
      throw new ConfigError(`${at}: holds a literal password; use { "env": "<VARIABLE>" }`);
    }
    if (CONNECTION_STRING_KEY.test(key)) {
      throw new ConfigError(`${at}: a literal connection string is not allowed; give server, port and databases as separate properties`);
    }
    refuseLiterals(value, at);
  }
}

export function loadConfig(configPath, { projectDir = process.cwd() } = {}) {
  if (typeof configPath !== 'string' || configPath === '') throw new ConfigError('--config <path> is required');
  let file;
  let project;
  try {
    file = realpathSync.native(configPath);
  } catch (error) {
    throw new ConfigError(`cannot read --config ${configPath}: ${error.code ?? error.message}`);
  }
  try {
    project = realpathSync.native(projectDir);
  } catch (error) {
    throw new ConfigError(`cannot resolve the project directory ${projectDir}: ${error.code ?? error.message}`);
  }
  if (isInside(file, project)) {
    throw new ConfigError(
      `--config ${configPath} is inside the project directory, which the agent can write; keep the config outside it`,
    );
  }
  let config;
  try {
    config = JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    // JSON.parse's message quotes the input, which may hold a credential.
    throw new ConfigError(`cannot parse --config ${configPath}: it is not valid JSON`);
  }
  if (typeof config !== 'object' || config === null || Array.isArray(config)) {
    throw new ConfigError('the config must be a JSON object');
  }
  if (!Object.hasOwn(config, 'schemaVersion')) throw new ConfigError('missing schemaVersion');
  if (config.schemaVersion !== SCHEMA_VERSION) {
    throw new ConfigError(
      `unknown schemaVersion ${JSON.stringify(config.schemaVersion)}; this plugin reads schemaVersion ${SCHEMA_VERSION}`,
    );
  }
  refuseLiterals(config, '');
  const errors = validateV1(config);
  if (errors.length) throw new ConfigError(`the config does not match config.v1.schema.json:\n${errors.join('\n')}`);
  return config;
}
