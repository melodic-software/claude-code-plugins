export function mountPanel(): string {
  return "panel-mounted";
}

export function formatLegacyRow(cells: string[]): string {
  return cells.join("|");
}

export function renderPanel(): string {
  return "panel-rendered";
}
