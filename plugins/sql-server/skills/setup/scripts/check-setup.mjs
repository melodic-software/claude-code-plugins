// The setup skill's check. Prints one PASS, FAIL or INFO row for the Node.js
// runtime, the config file, each environment it binds and, given --data-dir,
// the installed server copy, then the claude mcp add command that registers
// each environment. Prints variable names, never their values. Writes nothing.
//
// usage: node check-setup.mjs --config <path> [--environment <name>] [--data-dir <dir>]
// exit: 0 with no FAIL row, 1 with one, 2 on a usage error
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { ConfigError, loadConfig } from '../../../src/config.mjs';
import { bindRegistration } from '../../../src/registration.mjs';

const PLUGIN_ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const USAGE = 'usage: check-setup.mjs --config <path> [--environment <name>] [--data-dir <dir>]';
export const DEPENDENCIES = ['tedious', '@azure/identity'];

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
const shellQuote = (text) => (/^[\w@%+=:,./-]+$/.test(text) ? text : `'${text.replaceAll("'", "'\\''")}'`);

// install-server.mjs writes this manifest last, after npm ci succeeds, so its
// presence marks a finished copy.
export const installedVersion = (serverDir) => {
  const manifest = join(serverDir, '.claude-plugin', 'plugin.json');
  if (!existsSync(manifest)) return undefined;
  try {
    return String(readJson(manifest).version);
  } catch {
    return 'unreadable';
  }
};

export const missingDependencies = (serverDir) =>
  DEPENDENCIES.filter((name) => !existsSync(join(serverDir, 'node_modules', ...name.split('/'), 'package.json')));

function credentialVariables(auth) {
  return auth.type === 'sql-login' ? [auth.user.env, auth.password.env] : [];
}

// The variables reach the server as ${NAME} references the client expands at
// launch, so the stored registration holds no credential value.
export function registrationCommand({ environment, configPath, serverDir, auth }) {
  const envFlags = credentialVariables(auth).map((name) => `--env ${shellQuote(`${name}=\${${name}}`)}`);
  return [
    'claude mcp add',
    ...envFlags,
    '--transport stdio --scope user',
    `sql-${environment}`,
    '--',
    'node',
    shellQuote(join(serverDir, 'src', 'launch.mjs')),
    '--config',
    shellQuote(configPath),
    '--environment',
    environment,
  ].join(' ');
}

export function checkSetup({
  configPath,
  environment,
  dataDir,
  projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd(),
  env = process.env,
}) {
  const rows = [];
  const row = (status, item, detail) => rows.push({ status, item, detail });

  const engines = readJson(join(PLUGIN_ROOT, 'package.json')).engines.node;
  const minimum = Number(/\d+/.exec(engines)[0]);
  const major = Number(process.versions.node.split('.')[0]);
  row(major >= minimum ? 'PASS' : 'FAIL', 'node', `${process.versions.node}; the server needs ${engines}`);

  let config;
  try {
    config = loadConfig(configPath, { projectDir });
    row('PASS', 'config', `${resolve(configPath)} matches config.v1.schema.json and holds no literal credential`);
  } catch (error) {
    if (!(error instanceof ConfigError)) throw error;
    row('FAIL', 'config', error.message);
  }

  const serverDir = dataDir === undefined ? undefined : join(resolve(dataDir), 'server');
  if (serverDir === undefined) {
    row('INFO', 'server copy', 'not checked; pass --data-dir');
  } else {
    const installed = installedVersion(serverDir);
    const { version } = readJson(join(PLUGIN_ROOT, '.claude-plugin', 'plugin.json'));
    if (installed === undefined) {
      row('INFO', 'server copy', `none in ${serverDir}; run apply to install it`);
    } else if (installed !== version) {
      row('FAIL', 'server copy', `${serverDir} holds ${installed}, the plugin is ${version}; run apply`);
    } else {
      row('PASS', 'server copy', `${serverDir} holds ${installed}`);
      const missing = missingDependencies(serverDir);
      if (missing.length) row('FAIL', 'server dependencies', `${missing.join(', ')} not installed in ${serverDir}; run apply`);
      else row('PASS', 'server dependencies', `${DEPENDENCIES.join(', ')} installed`);
    }
  }

  if (config === undefined) return rows;
  const names = environment === undefined ? Object.keys(config.environments) : [environment];
  for (const name of names) {
    let registration;
    try {
      registration = bindRegistration(config, name);
    } catch (error) {
      if (!(error instanceof ConfigError)) throw error;
      row('FAIL', `environment ${name}`, error.message);
      continue;
    }
    const port = registration.port === undefined ? '' : `:${registration.port}`;
    row('PASS', `environment ${name}`, `${registration.server}${port}, databases ${registration.databases.join(', ')}`);
    if (registration.auth.type === 'entra-default') {
      row('INFO', `auth ${name}`, 'entra-default signs in with DefaultAzureCredential, such as an az login session');
    }
    for (const variable of credentialVariables(registration.auth)) {
      const set = typeof env[variable] === 'string' && env[variable] !== '';
      const detail = set ? 'is set in this shell' : 'is not set in this shell; the server needs it set where Claude Code starts';
      row('INFO', `auth ${name}`, `${variable} ${detail}`);
    }
    const command = registrationCommand({
      environment: name,
      configPath: resolve(configPath),
      serverDir: serverDir ?? '<data-dir>/server',
      auth: registration.auth,
    });
    row('INFO', `register ${name}`, command);
  }
  return rows;
}

function cli(argv) {
  let values;
  try {
    ({ values } = parseArgs({
      args: argv,
      options: { config: { type: 'string' }, environment: { type: 'string' }, 'data-dir': { type: 'string' } },
      strict: true,
      allowPositionals: false,
    }));
  } catch (error) {
    process.stderr.write(`${error.message}\n${USAGE}\n`);
    return 2;
  }
  if (!values.config) {
    process.stderr.write(`--config is required\n${USAGE}\n`);
    return 2;
  }
  if (values['data-dir'] === '') {
    process.stderr.write(`--data-dir is empty\n${USAGE}\n`);
    return 2;
  }
  const rows = checkSetup({ configPath: values.config, environment: values.environment, dataDir: values['data-dir'] });
  for (const { status, item, detail } of rows) process.stdout.write(`${status.padEnd(4)}  ${item}: ${detail}\n`);
  return rows.some((r) => r.status === 'FAIL') ? 1 : 0;
}

// argv[1] keeps a symlinked path while import.meta.url is the real one.
const isEntry = () => {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
};
if (process.argv[1] && isEntry()) process.exitCode = cli(process.argv.slice(2));
