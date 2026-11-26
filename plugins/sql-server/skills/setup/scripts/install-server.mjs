import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { DEPENDENCIES, installedVersion, missingDependencies } from './check-setup.mjs';

const PLUGIN_ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const USAGE = 'usage: install-server.mjs --data-dir <dir>';
const MANIFEST = join('.claude-plugin', 'plugin.json');
const COPIED = ['src', 'schemas', 'package.json', 'package-lock.json'];

function main(argv) {
  let values;
  try {
    ({ values } = parseArgs({ args: argv, options: { 'data-dir': { type: 'string' } }, strict: true }));
  } catch (error) {
    process.stderr.write(`${error.message}\n${USAGE}\n`);
    return 2;
  }
  if (!values['data-dir']) {
    process.stderr.write(`--data-dir is required\n${USAGE}\n`);
    return 2;
  }
  const serverDir = join(resolve(values['data-dir']), 'server');
  const { version } = JSON.parse(readFileSync(join(PLUGIN_ROOT, MANIFEST), 'utf8'));

  if (installedVersion(serverDir) === version && missingDependencies(serverDir).length === 0) {
    process.stdout.write(`unchanged: ${serverDir} holds ${version} with its dependencies\n`);
    return 0;
  }

  const stagingDir = `${serverDir}.next`;
  const previousDir = `${serverDir}.previous`;
  rmSync(stagingDir, { recursive: true, force: true });
  for (const path of [...COPIED, MANIFEST]) {
    const destination = join(stagingDir, path);
    mkdirSync(dirname(destination), { recursive: true });
    cpSync(join(PLUGIN_ROOT, path), destination, { recursive: true });
  }
  const npm = spawnSync('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], {
    cwd: stagingDir,
    stdio: ['ignore', 'inherit', 'inherit'],
    shell: process.platform === 'win32',
  });
  if (npm.status !== 0) {
    process.stderr.write(`npm ci failed in ${stagingDir} (${npm.error?.message ?? `exit ${npm.status}`}); ${serverDir} is unchanged\n`);
    return 1;
  }
  const staged = installedVersion(stagingDir);
  const missing = missingDependencies(stagingDir);
  if (staged !== version || missing.length) {
    process.stderr.write(`${stagingDir} holds ${staged ?? 'no server'}; missing: ${missing.join(', ') || 'none'}; ${serverDir} is unchanged\n`);
    return 1;
  }

  rmSync(previousDir, { recursive: true, force: true });
  const hadCopy = existsSync(serverDir);
  if (hadCopy) renameSync(serverDir, previousDir);
  try {
    renameSync(stagingDir, serverDir);
  } catch (error) {
    if (hadCopy) renameSync(previousDir, serverDir);
    process.stderr.write(`could not swap ${stagingDir} in (${error.message}); ${serverDir} is unchanged\n`);
    return 1;
  }
  rmSync(previousDir, { recursive: true, force: true });
  process.stdout.write(`installed: ${serverDir} holds ${installedVersion(serverDir)} with ${DEPENDENCIES.join(', ')}\n`);
  return 0;
}

process.exitCode = main(process.argv.slice(2));
