// Paired discrimination fixture for the knip (TS/JS) lane.
//
// mountPanel is statically imported by ts-entry.ts, so knip reads it as used.
// formatLegacyRow has no reference at all -- genuinely dead. renderPanel is
// reached only through the template-literal dynamic import in ts-entry.ts,
// which knip cannot resolve, so it is reported exactly like formatLegacyRow
// while being alive. Separating the two is adjudication's job, not knip's.

export function mountPanel(): string {
  return "panel-mounted";
}

export function formatLegacyRow(cells: string[]): string {
  return cells.join("|");
}

export function renderPanel(): string {
  return "panel-rendered";
}
