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
  const checklistPath = initWatchChecklist(absSlice, { force: true });

  let bootstrapSnapshot;
  try {
    bootstrapSnapshot = snapshotBootstrapContactSheets(absSlice);
  } catch {
  }

  return { sheetIndexPath, checklistPath, bootstrapSnapshot };
}
