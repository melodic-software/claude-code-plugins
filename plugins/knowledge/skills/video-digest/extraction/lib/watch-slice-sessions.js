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

const BOUNDARY_STAMP = /\[(\d+):(\d+)(?::(\d+))?\]/g;

/**
 * @param {string} boundaryLine e.g. "[0:57] welcome → [7:58] next segment" or "[1:05:30] ..."
 * @returns {{ startSec: number, endSec: number|null }}
 */
export function parseBoundaryLine(boundaryLine) {
  const stamps = [...boundaryLine.matchAll(BOUNDARY_STAMP)].map((m) =>
    m[3] === undefined
      ? Number(m[1]) * 60 + Number(m[2])
      : Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]),
  );
  return { startSec: stamps[0] ?? 0, endSec: stamps[1] ?? null };
}

/**
 * Every `## <n>.` section must carry a `**Boundary:**` line with a bracketed
 * stamp; one that does not rejects the whole inventory (returns no session),
 * so a gate cannot pass while skipping a session it failed to read.
 *
 * @param {string} claimInventoryBody
 * @returns {{ name: string, startSec: number, endSec: number|null }[]}
 */
export function parseSessionsFromClaimInventory(claimInventoryBody) {
  const sessions = [];
  const sections = claimInventoryBody.split(/^## \d+\.\s+/m).slice(1);
  for (const section of sections) {
    const nameLine = section.split("\n")[0]?.trim();
    const boundaryMatch = section.match(/\*\*Boundary:\*\*\s*(.+)/);
    // A boundary with no bracketed stamp would span the whole video.
    if (!nameLine || !boundaryMatch?.[1].match(BOUNDARY_STAMP)) return [];
    const { startSec, endSec } = parseBoundaryLine(boundaryMatch[1]);
    sessions.push({ name: nameLine, startSec, endSec });
  }
  return sessions;
}

/**
 * The sessions that overlap a ranged slice's `watch.json` `timeRange`, so its floors grade
 * only the part that was watched. An open session end, or an open range end, runs to the
 * end of the video. With no range every session is kept.
 *
 * @template {{ startSec: number, endSec: number|null }} Session
 * @param {readonly Session[]} sessions - full-video time
 * @param {{ fromSec: number, toSec: number|null }|null|undefined} timeRange
 * @returns {Session[]}
 */
export function sessionsInTimeRange(sessions, timeRange) {
  if (!timeRange) return [...sessions];
  const rangeEnd = timeRange.toSec ?? Number.POSITIVE_INFINITY;
  return sessions.filter(
    (session) =>
      session.startSec < rangeEnd &&
      (session.endSec ?? Number.POSITIVE_INFINITY) > timeRange.fromSec,
  );
}
