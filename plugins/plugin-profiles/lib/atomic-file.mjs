import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
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

/** A file's text, or null when it cannot be read. */
export function readText(path) {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

export function removeFile(path) {
  rmSync(path, { force: true });
}
