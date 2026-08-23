// The used-export control for the knip capture: formatBytes is statically
// imported by ts-entry.ts, so it must NOT appear anywhere in knip-report.json.

export function formatBytes(count: number): string {
  return `${count} B`;
}
