#!/usr/bin/env bash
# A fresh map-prototype repository: a README and one source file, with no workflow, no env template,
# no .env and no config file, so nothing says where an API key should be kept.
set -euo pipefail
mkdir -p src
cat >README.md <<'MD'
# store-finder

A prototype page that shows the nearest store on a map. Nothing is wired to a map provider yet.
MD
cat >src/index.js <<'JS'
// Renders the store list. The map provider is not chosen yet.
module.exports = function render(stores) {
  return stores.map((s) => `${s.name}: ${s.city}`).join('\n');
};
JS
