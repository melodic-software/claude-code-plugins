// Whole-file replacement that a reader never sees half done: write a temp file beside the target,
// run the caller's last check, then rename over the target.
//
//   replaceFile(path, text, {beforeRename}) -> void; the temp file is removed on any failure
//   removeFile(path) -> void; an absent file is fine
//
// Windows can refuse a rename while another process holds the target open (EPERM, EBUSY,
// EACCES), so the rename is retried a few times before the failure is passed on.
import { mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";

const RETRY_CODES = new Set(["EPERM", "EBUSY", "EACCES"]);
const RETRIES = 5;
const RETRY_MS = 50;

const pause = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function renameWithRetry(from, to) {
  for (let attempt = 1; ; attempt++) {
    try {
      return renameSync(from, to);
    } catch (error) {
      if (process.platform !== "win32" || !RETRY_CODES.has(error.code) || attempt >= RETRIES) throw error;
      pause(RETRY_MS * attempt);
    }
  }
}

export function replaceFile(path, text, { beforeRename = () => {} } = {}) {
  mkdirSync(dirname(path), { recursive: true });
  const temp = join(dirname(path), `.${basename(path)}.${process.pid}.${Date.now()}.tmp`);
  try {
    writeFileSync(temp, text, { flag: "wx" });
    beforeRename();
    renameWithRetry(temp, path);
  } catch (error) {
    rmSync(temp, { force: true });
    throw error;
  }
}

export function removeFile(path) {
  rmSync(path, { force: true });
}
