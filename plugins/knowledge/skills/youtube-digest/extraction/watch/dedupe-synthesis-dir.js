/**
 * Remove byte-identical duplicates from the key-frames/frames/ lane directory.
 */

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { synthesisNameQualityScore } from "./synthesis-naming.js";

/**
 * @param {string} filePath
 * @returns {string}
 */
export function hashFile(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

/**
 * @param {string} synthesisDir
 * @returns {{ kept: string[], removed: string[] }}
 */
export function dedupeSynthesisDir(synthesisDir) {
  const absDir = path.resolve(synthesisDir);
  if (!fs.existsSync(absDir)) return { kept: [], removed: [] };

  const files = fs.readdirSync(absDir).filter((f) => f.endsWith(".png"));
  /** @type {Map<string, string[]>} */
  const byHash = new Map();

  for (const file of files) {
    const hash = hashFile(path.join(absDir, file));
    if (!byHash.has(hash)) byHash.set(hash, []);
    byHash.get(hash).push(file);
  }

  const kept = [];
  const removed = [];

  for (const group of byHash.values()) {
    if (group.length === 1) {
      kept.push(group[0]);
      continue;
    }
    const sorted = [...group].sort(
      (a, b) => synthesisNameQualityScore(b) - synthesisNameQualityScore(a),
    );
    kept.push(sorted[0]);
    for (const file of sorted.slice(1)) {
      fs.unlinkSync(path.join(absDir, file));
      removed.push(file);
    }
  }

  return { kept, removed };
}
