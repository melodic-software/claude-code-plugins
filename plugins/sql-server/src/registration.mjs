// Binds one registration from its launch arguments, per ADR 0086 sections 2
// and 5 and its write-tier amendment: --config names the file, --environment
// the one server and database allow-list this process may reach, and --write
// opts in to the write tool. No tool argument can change it.
import { parseArgs } from 'node:util';
import { ConfigError } from './config.mjs';

export class UsageError extends Error {
  constructor(message) {
    super(message);
    this.name = 'UsageError';
  }
}

export const USAGE = 'usage: sql-server --config <path> --environment <name> [--write]';

export function parseRegistrationArgs(argv) {
  let values;
  try {
    ({ values } = parseArgs({
      args: argv,
      options: { config: { type: 'string' }, environment: { type: 'string' }, write: { type: 'boolean' } },
      strict: true,
      allowPositionals: false,
    }));
  } catch (error) {
    throw new UsageError(`${error.message}\n${USAGE}`);
  }
  for (const name of ['config', 'environment']) {
    if (typeof values[name] !== 'string' || values[name] === '') throw new UsageError(`--${name} is required\n${USAGE}`);
  }
  return { configPath: values.config, environment: values.environment, write: values.write === true };
}

// Two auth blocks name one principal when they read the same variables or the
// same Entra identity. Different variables holding one login go undetected.
const samePrincipal = (a, b) =>
  a.type === b.type && a.user?.env === b.user?.env && a.clientId?.toLowerCase() === b.clientId?.toLowerCase();

// A registration opts in to writes with --write; the environment must then
// name a write principal separate from its read one.
export function bindRegistration(config, environment, { write = false } = {}) {
  if (!Object.hasOwn(config.environments, environment)) {
    throw new ConfigError(
      `--environment ${environment} is not in the config; it names: ${Object.keys(config.environments).join(', ')}`,
    );
  }
  const entry = config.environments[environment];
  if (write && entry.write === undefined) {
    throw new ConfigError(`--write needs a write principal: environments.${environment}.write.auth is not in the config`);
  }
  if (write && samePrincipal(entry.auth, entry.write.auth)) {
    throw new ConfigError(`environments.${environment}.write.auth names the read principal; the write principal must be a separate login`);
  }
  return Object.freeze({
    environment,
    server: entry.server,
    port: entry.port,
    databases: Object.freeze([...entry.databases]),
    auth: entry.auth,
    limits: Object.freeze({ ...config.defaults, ...entry.limits }),
    ...(write ? { write: Object.freeze({ auth: entry.write.auth }) } : {}),
  });
}
