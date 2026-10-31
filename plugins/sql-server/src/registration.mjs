// Binds one registration from its launch arguments, per ADR 0086 sections 2
// and 5: --config names the file and --environment the one server and
// database allow-list this process may reach. No tool argument can change it.
import { parseArgs } from 'node:util';
import { ConfigError } from './config.mjs';

export class UsageError extends Error {
  constructor(message) {
    super(message);
    this.name = 'UsageError';
  }
}

export const USAGE = 'usage: sql-server --config <path> --environment <name>';

export function parseRegistrationArgs(argv) {
  let values;
  try {
    ({ values } = parseArgs({
      args: argv,
      options: { config: { type: 'string' }, environment: { type: 'string' } },
      strict: true,
      allowPositionals: false,
    }));
  } catch (error) {
    throw new UsageError(`${error.message}\n${USAGE}`);
  }
  for (const name of ['config', 'environment']) {
    if (typeof values[name] !== 'string' || values[name] === '') throw new UsageError(`--${name} is required\n${USAGE}`);
  }
  return { configPath: values.config, environment: values.environment };
}

export function bindRegistration(config, environment) {
  if (!Object.hasOwn(config.environments, environment)) {
    throw new ConfigError(
      `--environment ${environment} is not in the config; it names: ${Object.keys(config.environments).join(', ')}`,
    );
  }
  const entry = config.environments[environment];
  return Object.freeze({
    environment,
    server: entry.server,
    port: entry.port,
    databases: Object.freeze([...entry.databases]),
    auth: entry.auth,
    limits: Object.freeze({ ...config.defaults, ...entry.limits }),
  });
}
