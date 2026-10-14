#!/usr/bin/env bash
# Seed a Node 20 project and a plan that reaches for lodash by habit to deep-clone config.
set -euo pipefail

mkdir -p notes src
cat >package.json <<'JSON'
{
  "name": "config-loader",
  "type": "module",
  "engines": { "node": ">=20" },
  "dependencies": {}
}
JSON
cat >src/config.js <<'JS'
export function loadConfig(base, overrides) {
  const config = deepClone(base); // deepClone is not chosen yet: see notes/plan.md
  return Object.assign(config, overrides);
}
JS
cat >notes/plan.md <<'MD'
# Plan: deep-clone the config (drafted earlier this session)

- Add lodash as a dependency and use `_.cloneDeep` as `deepClone` in src/config.js. We always reach for lodash for this.
- The config objects are plain data: strings, numbers, arrays, nested objects and Date values.
MD
