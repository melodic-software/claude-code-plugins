/**
 * Deterministic post-bootstrap steps after run-watch.js (before agent vision phases).
 */

import path from "node:path";

import { exportSheetFrameIndex } from "./export-sheet-frame-index.js";
import { initWatchChecklist } from "./init-watch-checklist.js";
import { snapshotBootstrapContactSheets } from "./snapshot-bootstrap.js";

/**
 * @param {string} sliceDir
 * @returns {{ sheetIndexPath: string, checklistPath: string, bootstrapSnapshot?: { copied: number } }}
 */
export function postBootstrapSlice(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const sheetIndexPath = exportSheetFrameIndex(absSlice);
  const checklistPath = initWatchChecklist(absSlice);

  let bootstrapSnapshot;
  try {
    bootstrapSnapshot = snapshotBootstrapContactSheets(absSlice);
  } catch {
    // The snapshot is optional: a failure leaves it out of the result.
  }

  // Bootstrap metrics (contactSheetCount, selectedFrames) already land in
  // watch.json's `watching` phase via run-watch.js markPhaseComplete, so this
  // writes no separate progress file.
  return { sheetIndexPath, checklistPath, bootstrapSnapshot };
}
