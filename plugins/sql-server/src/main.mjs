// Starts one registration's stdio server: bind the registration, build its
// executor, serve until stdin ends. Returns the process exit code.
import { readFileSync } from 'node:fs';
import { ConfigError, loadConfig } from './config.mjs';
import { UsageError, bindRegistration, parseRegistrationArgs } from './registration.mjs';
import { createServer, serveStdio } from './server.mjs';

const { version } = JSON.parse(readFileSync(new URL('../.claude-plugin/plugin.json', import.meta.url), 'utf8'));

const NO_EXECUTOR = 'this release has no database executor, so no call reaches a database yet';

// Refuses every call as a tool error until a release ships the real executor.
export function pendingExecutor() {
  const refuse = async () => {
    throw new Error(NO_EXECUTOR);
  };
  return { query: refuse, listObjects: refuse, describeObject: refuse };
}

export async function main({
  argv = process.argv.slice(2),
  createExecutor = pendingExecutor,
  input = process.stdin,
  output = process.stdout,
  stderr = process.stderr,
  projectDir = process.cwd(),
} = {}) {
  let registration;
  try {
    const { configPath, environment } = parseRegistrationArgs(argv);
    registration = bindRegistration(loadConfig(configPath, { projectDir }), environment);
  } catch (error) {
    if (error instanceof UsageError || error instanceof ConfigError) {
      stderr.write(`sql-server: ${error.message}\n`);
      return 2;
    }
    throw error;
  }
  const executor = createExecutor(registration);
  const server = createServer({
    databases: registration.databases,
    executor,
    serverInfo: { name: 'sql-server', version },
    log: (line) => stderr.write(`${line}\n`),
  });
  try {
    await serveStdio(server, { input, output });
  } finally {
    await executor.close?.();
  }
  return 0;
}
