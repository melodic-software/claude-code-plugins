#!/usr/bin/env node
/**
 * Exclusive row claims for `.work/<watch-epic>/claims/<n>.json` (canonical epic dir: derive-video-slug.js).
 *
 * Usage:
 *   node watch/queue-claim.js claim <row> [--video-id <id>] [--claimed-by <id>] [--epic-dir <path>]
 *   node watch/queue-claim.js release <row> [--epic-dir <path>]
 *   node watch/queue-claim.js list [--epic-dir <path>]
 *   node watch/queue-claim.js stale-check [--epic-dir <path>] [--max-age-days 7]
 *   node watch/queue-claim.js next [--epic-dir <path>]
 *   node watch/queue-claim.js hold <row> --next-check <iso> --deadline <iso> [--epic-dir <path>]
 *   node watch/queue-claim.js resume <row> [--notes <text>] [--epic-dir <path>]
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { toIsoTime } from "../acquisition/caption-wait.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { YOUTUBE_WATCH_EPIC_DIR } from "../transcript/derive-video-slug.js";

/** @typedef {{ row: number, videoId: string | null, claimedAt: string, claimedBy: string }} QueueClaim */

export const DEFAULT_STALE_DAYS = 7;

/** Row status of a live-derived video held until its captions are published. */
export const AWAITING_CAPTIONS = "awaiting_captions";

const ISO_TIME = String.raw`(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)`;
const NEXT_CHECK_PATTERN = new RegExp(String.raw`\bnext check ${ISO_TIME}`);
const DEADLINE_PATTERN = new RegExp(String.raw`\bdeadline ${ISO_TIME}`);

/**
 * @param {string} [workRoot]
 * @returns {string}
 */
export function resolveEpicDir(workRoot = resolveWorkRoot()) {
  return path.join(workRoot, ".work", YOUTUBE_WATCH_EPIC_DIR);
}

/**
 * @param {string} epicDir
 * @returns {string}
 */
function claimsDirPath(epicDir) {
  return path.join(epicDir, "claims");
}

/**
 * @param {string} epicDir
 * @param {number} row
 * @returns {string}
 */
export function claimFilePath(epicDir, row) {
  return path.join(claimsDirPath(epicDir), `${row}.json`);
}

/**
 * @returns {string}
 */
export function defaultClaimedBy() {
  const host = os.hostname().replace(/[^\w.-]/g, "-");
  return `${host}-pid${process.pid}`;
}

/**
 * @param {QueueClaim} claim
 * @param {number} [maxAgeDays]
 * @returns {boolean}
 */
export function isStaleClaim(claim, maxAgeDays = DEFAULT_STALE_DAYS) {
  const claimedMs = Date.parse(claim.claimedAt);
  if (Number.isNaN(claimedMs)) {
    return true;
  }
  const maxMs = maxAgeDays * 24 * 60 * 60 * 1000;
  return Date.now() - claimedMs > maxMs;
}

/**
 * @param {string} epicDir
 * @param {number} row
 * @param {{ videoId?: string | null, claimedBy?: string }} [options]
 * @returns {QueueClaim}
 */
export function claimRow(epicDir, row, { videoId = null, claimedBy = defaultClaimedBy() } = {}) {
  if (!Number.isInteger(row) || row < 1) {
    throw new Error(`Invalid row: ${row}`);
  }

  fs.mkdirSync(claimsDirPath(epicDir), { recursive: true });

  const filePath = claimFilePath(epicDir, row);
  /** @type {QueueClaim} */
  const payload = { row, videoId, claimedAt: new Date().toISOString(), claimedBy };

  let handle;
  try {
    handle = fs.openSync(filePath, "wx");
    fs.writeFileSync(handle, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  } catch (err) {
    if (/** @type {NodeJS.ErrnoException} */ (err).code === "EEXIST") {
      const existing = readClaimFile(filePath);
      const error = new Error(
        `Row ${row} already claimed by ${existing.claimedBy} at ${existing.claimedAt}`,
      );
      error.name = "ClaimExistsError";
      throw error;
    }
    throw err;
  } finally {
    if (handle !== undefined) {
      fs.closeSync(handle);
    }
  }

  return payload;
}

/**
 * @param {string} filePath
 * @returns {QueueClaim}
 */
export function readClaimFile(filePath) {
  return /** @type {QueueClaim} */ (JSON.parse(fs.readFileSync(filePath, "utf8")));
}

/**
 * @param {string} epicDir
 * @param {number} row
 * @returns {boolean}
 */
export function releaseRow(epicDir, row) {
  const filePath = claimFilePath(epicDir, row);
  if (!fs.existsSync(filePath)) {
    return false;
  }
  fs.unlinkSync(filePath);
  return true;
}

/**
 * @param {string} epicDir
 * @returns {QueueClaim[]}
 */
export function listClaims(epicDir) {
  const claimsDir = claimsDirPath(epicDir);
  if (!fs.existsSync(claimsDir)) {
    return [];
  }

  const claims = [];
  for (const name of fs.readdirSync(claimsDir)) {
    if (!name.endsWith(".json")) {
      continue;
    }
    const filePath = path.join(claimsDir, name);
    try {
      claims.push(readClaimFile(filePath));
    } catch {
      writeStderr(`WARN: unreadable claim file ${filePath}`);
    }
  }

  return claims.sort((a, b) => a.row - b.row);
}

/**
 * @param {string} epicDir
 * @returns {string}
 */
export function queueFilePath(epicDir) {
  return path.join(epicDir, "QUEUE.md");
}

/**
 * Split a markdown table line into trimmed cells, honoring `\|` escapes.
 * @param {string} line
 * @returns {string[]}
 */
function splitTableRow(line) {
  const cells = [];
  let current = "";
  const body = line.trim().replace(/^\|/, "").replace(/\|$/, "");
  for (let i = 0; i < body.length; i++) {
    if (body[i] === "\\" && body[i + 1] === "|") {
      current += "\\|";
      i++;
    } else if (body[i] === "|") {
      cells.push(current.trim());
      current = "";
    } else {
      current += body[i];
    }
  }
  cells.push(current.trim());
  return cells;
}

/**
 * Parse `QUEUE.md` into `{ row, status, notes }` entries; `null` when the file is absent.
 * @param {string} epicDir
 * @returns {{ lines: string[], statusIndex: number, notesIndex: number, entries: { row: number, status: string, notes: string, lineIndex: number }[] } | null}
 */
function readQueueTable(epicDir) {
  const filePath = queueFilePath(epicDir);
  if (!fs.existsSync(filePath)) {
    return null;
  }
  const lines = fs.readFileSync(filePath, "utf8").split("\n");
  let statusIndex = -1;
  let notesIndex = -1;
  const entries = [];
  for (const [lineIndex, line] of lines.entries()) {
    if (!line.trim().startsWith("|")) {
      continue;
    }
    const cells = splitTableRow(line);
    if (statusIndex === -1) {
      if (cells[0] === "#") {
        statusIndex = cells.indexOf("status");
        notesIndex = cells.indexOf("notes");
      }
      continue;
    }
    if (!/^\d+$/.test(cells[0] ?? "")) {
      continue;
    }
    entries.push({
      row: Number(cells[0]),
      status: cells[statusIndex] ?? "",
      notes: notesIndex === -1 ? "" : (cells[notesIndex] ?? ""),
      lineIndex,
    });
  }
  return { lines, statusIndex, notesIndex, entries };
}

/**
 * @param {string} epicDir
 * @returns {{ row: number, status: string }[] | null}
 */
export function readQueueRows(epicDir) {
  const table = readQueueTable(epicDir);
  return table ? table.entries.map(({ row, status }) => ({ row, status })) : null;
}

/**
 * Set a `QUEUE.md` row's status when it currently equals `from`.
 * @param {string} epicDir
 * @param {number} row
 * @param {string} from
 * @param {string} to
 * @returns {boolean} true when the row was rewritten
 */
export function setRowStatus(epicDir, row, from, to) {
  return rewriteRow(epicDir, row, [from], { status: to });
}

/**
 * Rewrite a `QUEUE.md` row's status, and its notes when given, when its status is one of `from`.
 * @param {string} epicDir
 * @param {number} row
 * @param {string[]} from
 * @param {{ status: string, notes?: string }} next
 * @returns {boolean} true when the row was rewritten
 */
function rewriteRow(epicDir, row, from, { status, notes }) {
  const table = readQueueTable(epicDir);
  const entry = table?.entries.find((e) => e.row === row);
  if (!(table && entry) || !from.includes(entry.status)) {
    return false;
  }
  const cells = splitTableRow(table.lines[entry.lineIndex]);
  cells[table.statusIndex] = status;
  if (notes !== undefined && table.notesIndex !== -1) {
    cells[table.notesIndex] = notes.replace(/\s+/g, " ").trim().replace(/(?<!\\)\|/g, "\\|");
  }
  table.lines[entry.lineIndex] = `| ${cells.join(" | ")} |`;
  fs.writeFileSync(queueFilePath(epicDir), table.lines.join("\n"), "utf8");
  return true;
}

/**
 * The `notes` cell of a row held for captions.
 * @param {{ nextCheckAt: string, deadline: string }} wait
 * @returns {string}
 */
export function captionWaitNotes({ nextCheckAt, deadline }) {
  return `awaiting captions: next check ${nextCheckAt}, deadline ${deadline}`;
}

/**
 * The caption-wait times a row's `notes` records; null for each one it lacks.
 * @param {string} notes
 * @returns {{ nextCheckAt: string | null, deadline: string | null }}
 */
export function parseCaptionWaitNotes(notes) {
  return {
    nextCheckAt: NEXT_CHECK_PATTERN.exec(notes)?.[1] ?? null,
    deadline: DEADLINE_PATTERN.exec(notes)?.[1] ?? null,
  };
}

/**
 * Whether a held row's next check time has come. A row whose notes lost the time is due,
 * so it is never held for good.
 * @param {string} notes
 * @param {number} nowMs
 * @returns {boolean}
 */
function isRecheckDue(notes, nowMs) {
  const { nextCheckAt } = parseCaptionWaitNotes(notes);
  return nextCheckAt === null || Date.parse(nextCheckAt) <= nowMs;
}

/**
 * Hold row `#n` for captions: `in_progress` (first hold) or `awaiting_captions` (a re-check
 * that found none) → `awaiting_captions`, with the next check time and deadline in `notes`.
 * A `QUEUE.md` with no `notes` column cannot record those times, so the hold is refused.
 * @param {string} epicDir
 * @param {number} row
 * @param {{ nextCheckAt: string, deadline: string }} wait
 * @returns {boolean} true when the row was rewritten
 */
export function holdRowForCaptions(epicDir, row, wait) {
  if (readQueueTable(epicDir)?.notesIndex === -1) {
    return false;
  }
  return rewriteRow(epicDir, row, ["in_progress", AWAITING_CAPTIONS], {
    status: AWAITING_CAPTIONS,
    notes: captionWaitNotes(wait),
  });
}

/**
 * Return a held row to `pending`: its captions appeared, or its wait ended. `notes` replaces
 * the hold's notes; an ended wait keeps its deadline there so the watch run reads it.
 * @param {string} epicDir
 * @param {number} row
 * @param {string} [notes]
 * @returns {boolean} true when the row was rewritten
 */
export function resumeRowFromCaptionWait(epicDir, row, notes = "") {
  return rewriteRow(epicDir, row, [AWAITING_CAPTIONS], { status: "pending", notes });
}

/**
 * Rows FIFO `watch` may claim, in `#` order: each unclaimed `pending` row, and each unclaimed
 * `awaiting_captions` row whose next check time has come (`recheck: true`, a caption re-check
 * before any watch). A held row before its check time is skipped. A held row whose notes
 * record no deadline cannot be re-checked (`caption-recheck.js` requires one), so it is listed
 * with `recheck: false`: its watch starts a new caption wait, as a `pending` row's would.
 * @param {string} epicDir
 * @param {number} [nowMs]
 * @returns {{ row: number, status: string, recheck: boolean, captionWaitDeadline: string | null }[]}
 */
export function claimableRows(epicDir, nowMs = Date.now()) {
  const claimed = new Set(listClaims(epicDir).map((c) => c.row));
  return (readQueueTable(epicDir)?.entries ?? [])
    .filter((e) => !claimed.has(e.row))
    .filter(
      (e) =>
        e.status === "pending" ||
        (e.status === AWAITING_CAPTIONS && isRecheckDue(e.notes, nowMs)),
    )
    .map((e) => {
      const captionWaitDeadline = parseCaptionWaitNotes(e.notes).deadline;
      return {
        row: e.row,
        status: e.status,
        recheck: e.status === AWAITING_CAPTIONS && captionWaitDeadline !== null,
        captionWaitDeadline,
      };
    });
}

/**
 * Release stale claim stubs and reset their `in_progress` rows to `pending`.
 * `orphaned` lists `in_progress` rows with no claim stub (a run that crashed
 * before writing one); they are reported, not changed, since no age is known.
 * An `awaiting_captions` row is never reset or orphaned: `captionRecheckDue`
 * lists the unclaimed ones whose next check time has come.
 * @param {string} epicDir
 * @param {number} [maxAgeDays]
 * @param {number} [nowMs]
 * @returns {{ released: number[], rows: number[], reset: number[], orphaned: number[], captionRecheckDue: number[] }}
 */
export function reclaimStaleClaims(epicDir, maxAgeDays = DEFAULT_STALE_DAYS, nowMs = Date.now()) {
  const released = [];
  const reset = [];
  for (const claim of listClaims(epicDir)) {
    if (!isStaleClaim(claim, maxAgeDays)) {
      continue;
    }
    if (releaseRow(epicDir, claim.row)) {
      released.push(claim.row);
      if (setRowStatus(epicDir, claim.row, "in_progress", "pending")) {
        reset.push(claim.row);
      }
    }
  }
  const claimed = new Set(listClaims(epicDir).map((c) => c.row));
  const orphaned = (readQueueRows(epicDir) ?? [])
    .filter((e) => e.status === "in_progress" && !claimed.has(e.row))
    .map((e) => e.row);
  const captionRecheckDue = claimableRows(epicDir, nowMs)
    .filter((e) => e.recheck)
    .map((e) => e.row);
  return { released, rows: released, reset, orphaned, captionRecheckDue };
}

/**
 * @param {string[]} argv
 */
// biome-ignore lint/complexity/noExcessiveCognitiveComplexity: CLI dispatches claim/release/list/stale-check/next/hold/resume subcommands
function main(argv) {
  const args = argv.slice(2);
  const command = args[0];
  if (!command) {
    writeStderr("Usage: queue-claim.js <claim|release|list|stale-check|next|hold|resume> ...");
    process.exit(1);
  }

  let epicDir = resolveEpicDir();
  let maxAgeDays = DEFAULT_STALE_DAYS;
  /** First `--video-id` wins; a repeated flag is ignored. */
  /** @type {string | null} */
  let videoId = null;
  /** Caller-supplied holder name; the default names this short-lived child process. */
  let claimedBy;
  /** `hold` times and the `resume` notes. */
  let nextCheckAt = "";
  let deadline = "";
  let notes = "";
  const rows = [];

  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--epic-dir" && args[i + 1]) {
      epicDir = path.resolve(args[++i]);
      continue;
    }
    if (arg === "--max-age-days" && args[i + 1]) {
      maxAgeDays = Number(args[++i]);
      continue;
    }
    if (arg === "--video-id" && args[i + 1]) {
      const value = args[++i];
      if (videoId === null) videoId = value;
      continue;
    }
    if (arg === "--claimed-by" && args[i + 1]) {
      claimedBy = args[++i];
      continue;
    }
    if (arg === "--next-check" && args[i + 1]) {
      nextCheckAt = args[++i];
      continue;
    }
    if (arg === "--deadline" && args[i + 1]) {
      deadline = args[++i];
      continue;
    }
    if (arg === "--notes" && args[i + 1]) {
      notes = args[++i];
      continue;
    }
    rows.push(arg);
  }

  if (command === "list") {
    const claims = listClaims(epicDir);
    writeStdout(JSON.stringify({ epicDir, claims }, null, 2));
    return;
  }

  if (command === "next") {
    writeStdout(JSON.stringify({ epicDir, rows: claimableRows(epicDir) }, null, 2));
    return;
  }

  if (command === "stale-check") {
    const result = reclaimStaleClaims(epicDir, maxAgeDays);
    writeStdout(JSON.stringify({ epicDir, maxAgeDays, ...result }, null, 2));
    return;
  }

  const rowToken = rows[0];
  if (rowToken === undefined) {
    writeStderr(`Missing row for ${command}`);
    process.exit(1);
  }

  const row = Number(rowToken);
  if (!Number.isInteger(row) || row < 1) {
    writeStderr(`Invalid row: ${rowToken}`);
    process.exit(1);
  }

  if (command === "claim") {
    if (!readQueueRows(epicDir)?.some((e) => e.row === row)) {
      writeStderr(`Row ${row} is not in ${queueFilePath(epicDir)}`);
      process.exit(1);
    }
    try {
      const claim = claimRow(epicDir, row, { videoId, claimedBy });
      writeStdout(JSON.stringify({ ok: true, claim }, null, 2));
    } catch (err) {
      if (/** @type {Error} */ (err).name === "ClaimExistsError") {
        writeStderr(err.message);
        process.exit(2);
      }
      throw err;
    }
    return;
  }

  if (command === "release") {
    const released = releaseRow(epicDir, row);
    writeStdout(JSON.stringify({ ok: released, row }, null, 2));
    if (!released) {
      process.exit(1);
    }
    return;
  }

  if (command === "hold") {
    const wait = { nextCheckAt: toIsoTime(nextCheckAt), deadline: toIsoTime(deadline) };
    if (!(wait.nextCheckAt && wait.deadline)) {
      writeStderr("hold requires --next-check <iso> and --deadline <iso>");
      process.exit(1);
    }
    const held = holdRowForCaptions(epicDir, row, {
      nextCheckAt: wait.nextCheckAt,
      deadline: wait.deadline,
    });
    writeStdout(JSON.stringify({ ok: held, row, status: AWAITING_CAPTIONS }, null, 2));
    if (!held) {
      process.exit(1);
    }
    return;
  }

  if (command === "resume") {
    const resumed = resumeRowFromCaptionWait(epicDir, row, notes);
    writeStdout(JSON.stringify({ ok: resumed, row, status: "pending" }, null, 2));
    if (!resumed) {
      process.exit(1);
    }
    return;
  }

  writeStderr(`Unknown command: ${command}`);
  process.exit(1);
}

if (isMainModule(import.meta.url)) {
  main(process.argv);
}
