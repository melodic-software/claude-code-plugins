// Standalone-module control for the grep lane: no package.json root owns this file.
// One function nothing calls, and one the module calls itself.

export function renderLegacyRow(cells) {
  return cells.join("|");
}

export function summarizeRows(rows) {
  return `${rows.length} rows`;
}

console.log(summarizeRows(["a", "b"]));
