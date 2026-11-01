// The setup skill's apply. Copies the server (src, schemas, package.json,
// package-lock.json and the plugin manifest) into <data-dir>/server, a path
// that stays the same across plugin updates, and installs its pinned
// dependencies with npm ci in <data-dir>/server.next, which replaces the live
// copy only once complete. Changes nothing when that copy already holds this
// plugin's version and its dependencies. Prints the version it reads back.
//
// usage: node install-server.mjs --data-dir <dir>
// exit: 0 when the copy holds this version and its dependencies, 1 when not, 2 on a usage error
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
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
  const { version } = JSON.parse(readFileSync(join(PLUGIN_ROOT, '.claude-plugin', 'plugin.json'), 'utf8'));

  if (installedVersion(serverDir) === version && missingDependencies(serverDir).length === 0) {
    process.stdout.write(`unchanged: ${serverDir} holds ${version} with its dependencies\n`);
    return 0;
  }

  // Build the new copy beside the live one and swap it in only once it is
  // complete, so a failed install leaves the copy registrations use untouched.
  const stagingDir = `${serverDir}.next`;
  const previousDir = `${serverDir}.previous`;
  rmSync(stagingDir, { recursive: true, force: true });
  for (const path of [...COPIED, MANIFEST]) {
    mkdirSync(join(stagingDir, path, '..'), { recursive: true });
    cpSync(join(PLUGIN_ROOT, path), join(stagingDir, path), { recursive: true });
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
