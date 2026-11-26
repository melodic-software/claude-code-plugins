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

const samePrincipal = (a, b) =>
  a.type === b.type && a.user?.env === b.user?.env && a.clientId?.toLowerCase() === b.clientId?.toLowerCase();

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
