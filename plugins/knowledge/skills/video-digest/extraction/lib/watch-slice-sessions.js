/**
 * Parse session boundaries from slice claim-inventory markdown (video-agnostic).
 */

/**
 * The only session shape the parser reads, for messages that reject an
 * inventory with no parsed session. `context/watch-pipeline.md` Phase 2 shows it.
 */
export const SESSION_FORMAT_HINT =
  "write each session as a `## <n>. <name>` heading followed by a " +
  "`**Boundary:** [m:ss] <label> → [m:ss] <label>` line ([h:mm:ss] also accepted); " +
  "a session table is not parsed";

/**
 * @param {string} boundaryLine e.g. "[0:57] welcome → [7:58] next segment" or "[1:05:30] ..."
 * @returns {{ startSec: number, endSec: number|null }}
 */
export function parseBoundaryLine(boundaryLine) {
  const stamps = [...boundaryLine.matchAll(/\[(\d+):(\d+)(?::(\d+))?\]/g)].map((m) =>
    m[3] === undefined
      ? Number(m[1]) * 60 + Number(m[2])
      : Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]),
  );
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
