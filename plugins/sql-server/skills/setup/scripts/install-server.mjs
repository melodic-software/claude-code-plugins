// The setup skill's apply. Copies the server (src, schemas, package.json,
// package-lock.json and the plugin manifest) into <data-dir>/server, a path
// that stays the same across plugin updates, and installs its pinned
// dependencies there with npm ci. Changes nothing when that copy already holds
// this plugin's version and its dependencies. Prints the version it reads back.
//
// usage: node install-server.mjs --data-dir <dir>
// exit: 0 when the copy holds this version and its dependencies, 1 when not, 2 on a usage error
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
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

  // The manifest goes first and comes back last, after npm ci succeeds, so an
  // interrupted install leaves no copy that claims a version.
  rmSync(join(serverDir, MANIFEST), { force: true });
  const copy = (path) => {
    rmSync(join(serverDir, path), { recursive: true, force: true });
    mkdirSync(join(serverDir, path, '..'), { recursive: true });
    cpSync(join(PLUGIN_ROOT, path), join(serverDir, path), { recursive: true });
  };
  COPIED.forEach(copy);
  const npm = spawnSync('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], {
    cwd: serverDir,
    stdio: ['ignore', 'inherit', 'inherit'],
    shell: process.platform === 'win32',
  });
  if (npm.status !== 0) {
    process.stderr.write(`npm ci failed in ${serverDir} (${npm.error?.message ?? `exit ${npm.status}`})\n`);
    return 1;
  }
  copy(MANIFEST);

  const installed = installedVersion(serverDir);
  const missing = missingDependencies(serverDir);
  if (installed !== version || missing.length) {
    process.stderr.write(`${serverDir} holds ${installed ?? 'no server'}; missing: ${missing.join(', ') || 'none'}\n`);
    return 1;
  }
  process.stdout.write(`installed: ${serverDir} holds ${installed} with ${DEPENDENCIES.join(', ')}\n`);
  return 0;
}

process.exitCode = main(process.argv.slice(2));
