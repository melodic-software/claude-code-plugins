#!/usr/bin/env bash
# Runs measure-layers.mjs and compares every defect-by-layer cell, and the
# geometry check behind each geometry catch, with expected-matrix.json. The
# expected cells come from the defect catalog's "Layers expected to catch it"
# column; expected-matrix.json lists each cell that differs and why.
# Skips (exit 0) when the one-time cache in README.md is not installed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../../../.." && pwd)"

# shellcheck source=../../../../../../scripts/lib/python-probe.sh
. "$ROOT/scripts/lib/python-probe.sh"
PYTHON=""
python_probe::require_to PYTHON "$HERE/../build-variants.py"

if ! command -v node >/dev/null 2>&1 || [[ ! -d "$HERE/node_modules/@axe-core/playwright" ]]; then
  echo "SKIP: node or harness/node_modules missing; install per $HERE/README.md"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

status=0
node "$HERE/measure-layers.mjs" --python "$PYTHON" --out "$TMP/measured.json" >"$TMP/log" 2>&1 || status=$?
if [[ $status -eq 2 ]]; then
  echo "SKIP: $(tail -n 1 "$TMP/log")"
  exit 0
fi
if [[ $status -ne 0 ]]; then
  cat "$TMP/log" >&2
  echo "FAIL: measure-layers.mjs exited $status" >&2
  exit 1
fi

node - "$HERE/expected-matrix.json" "$TMP/measured.json" <<'JS'
const { readFileSync } = require('node:fs');
const [expected, measured] = process.argv.slice(2).map((p) => JSON.parse(readFileSync(p, 'utf8')));
const errors = [];
if (measured.aborted !== 0) errors.push(`aborted ${measured.aborted} non-file request(s)`);
const ids = Object.keys(expected.matrix).sort();
if (JSON.stringify(Object.keys(measured.matrix).sort()) !== JSON.stringify(ids))
  errors.push(`variants ${Object.keys(measured.matrix)} != ${ids}`);
for (const id of ids)
  for (const layer of expected.layers) {
    const want = expected.matrix[id][layer];
    const got = measured.matrix[id]?.[layer];
    if (got !== want) errors.push(`${id} ${layer}: expected ${want}, measured ${got}`);
  }
for (const id of ids) {
  const want = JSON.stringify(expected.geometry_checks[id]);
  const got = JSON.stringify(measured.geometry_checks[id]);
  if (got !== want) errors.push(`${id} geometry checks: expected ${want}, measured ${got}`);
}
if (Object.values(measured.matrix.C0 ?? { missing: true }).some(Boolean)) errors.push('C0 has a finding');
if (errors.length) {
  for (const e of errors) console.error(`FAIL: ${e}`);
  process.exit(1);
}
const v = measured.versions;
console.log(`PASS: ${ids.length} variants x ${expected.layers.length} layers (axe-core ${v['axe-core']}, playwright-core ${v['playwright-core']}, chromium ${v.chromium})`);
JS
