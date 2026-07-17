/**
 * Parse session boundaries from slice claim-inventory markdown (video-agnostic).
 */

/**
 * @param {string} boundaryLine e.g. "[0:57] welcome → [7:58] next segment"
 * @returns {{ startSec: number, endSec: number|null }}
 */
export function parseBoundaryLine(boundaryLine) {
  const stamps = [...boundaryLine.matchAll(/\[(\d+):(\d+)\]/g)].map((m) => {
    return Number(m[1]) * 60 + Number(m[2]);
  });
  return { startSec: stamps[0] ?? 0, endSec: stamps[1] ?? null };
}

/**
 * @param {string} claimInventoryBody
 * @returns {{ name: string, startSec: number, endSec: number|null }[]}
 */
export function parseSessionsFromClaimInventory(claimInventoryBody) {
  const sessions = [];
  const sections = claimInventoryBody.split(/^## \d+\.\s+/m).slice(1);
  for (const section of sections) {
    const nameLine = section.split("\n")[0]?.trim();
    const boundaryMatch = section.match(/\*\*Boundary:\*\*\s*(.+)/);
    if (!nameLine || !boundaryMatch) continue;
    const { startSec, endSec } = parseBoundaryLine(boundaryMatch[1]);
    sessions.push({ name: nameLine, startSec, endSec });
  }
  return sessions;
}
