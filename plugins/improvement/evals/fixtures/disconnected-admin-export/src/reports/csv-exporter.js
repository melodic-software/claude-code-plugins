export function exportRowsToCsv(rows, columns) {
  const header = columns.join(",");
  const lines = rows.map((row) => columns.map((c) => JSON.stringify(row[c] ?? "")).join(","));
  return [header, ...lines].join("\n");
}
