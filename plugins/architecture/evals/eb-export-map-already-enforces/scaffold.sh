#!/usr/bin/env bash
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore AGENTS.md docs package.json packages node_modules scripts .tools
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh"

cat >>docs/conventions/architecture/README.md <<'MD'

## Boundary rules

- Another package that imports billing by package name, tests included, uses only its root specifier `@shop/billing`, never a subpath such as `@shop/billing/src/ledger.js`. Imports by relative path are not covered by this rule. Evidence: packages/billing/package.json:4, packages/reporting/src/report.js:1. Accepted 2026-10-30.
MD

mkdir -p packages/billing/src packages/reporting/src packages/reporting/test scripts node_modules/@shop
printf 'node_modules/\n' >.gitignore

cat >package.json <<'JSON'
{
  "name": "shop",
  "private": true,
  "type": "module",
  "workspaces": ["packages/*"],
  "scripts": {
    "check": "bash scripts/check.sh"
  }
}
JSON

cat >packages/billing/package.json <<'JSON'
{
  "name": "@shop/billing",
  "type": "module",
  "exports": { ".": "./src/index.js" }
}
JSON

cat >packages/billing/src/ledger.js <<'JS'
export function balance(entries) {
  return entries.reduce((total, entry) => total + entry.cents, 0);
}
JS

cat >packages/billing/src/index.js <<'JS'
import { balance } from './ledger.js';

export function outstanding(entries) {
  return balance(entries.filter((entry) => !entry.paid));
}
JS

cat >packages/reporting/package.json <<'JSON'
{
  "name": "@shop/reporting",
  "type": "module",
  "exports": { ".": "./src/report.js" },
  "dependencies": { "@shop/billing": "*" }
}
JSON

cat >packages/reporting/src/report.js <<'JS'
import { outstanding } from '@shop/billing';

export function summary(entries) {
  return `outstanding: ${outstanding(entries)}`;
}
JS

cat >packages/reporting/test/report.test.js <<'JS'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summary } from '@shop/reporting';

test('summary counts unpaid entries only', () => {
  assert.equal(summary([{ cents: 250, paid: false }, { cents: 100, paid: true }]), 'outstanding: 250');
});
JS

cat >scripts/load-sources.mjs <<'JS'
// Imports every package source file, so the resolver checks each import in the workspace.
import { readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

for (const pkg of readdirSync('packages')) {
  const src = join('packages', pkg, 'src');
  for (const file of readdirSync(src, { recursive: true })) {
    if (file.endsWith('.js')) await import(pathToFileURL(resolve(src, file)).href);
  }
}
JS

cat >scripts/check.sh <<'SH'
#!/usr/bin/env bash
# Runs every check this repository has. CI runs this file.
set -euo pipefail
PATH="$(pwd)/.tools:${PATH}"
node scripts/load-sources.mjs
node --test
SH

ln -s ../../packages/billing node_modules/@shop/billing
ln -s ../../packages/reporting node_modules/@shop/reporting

node_bin="$(node -e 'process.stdout.write(process.execPath)' 2>/dev/null || true)"
if [[ ! -x "${node_bin}" ]]; then
  shim_dir="$(dirname "$(command -v node)")"
  installed=("${shim_dir}"/../installs/node/*/bin/node)
  node_bin="${installed[${#installed[@]} - 1]}"
fi
[[ -x "${node_bin}" ]] || { echo "scaffold needs a node binary" >&2 && exit 1; }
mkdir -p .tools
ln -L "${node_bin}" .tools/node 2>/dev/null || cp -L "${node_bin}" .tools/node
printf '.tools/\n' >>.gitignore
cat >>AGENTS.md <<'MD'

Node for this repository is `.tools/node`; run it as `PATH="$PWD/.tools:$PATH" node`. `scripts/check.sh` puts it on `PATH` itself.
MD

git add -A
git commit -q -m "Billing and reporting packages with an exports map and a check script"
