import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const dirs = [];
process.on("exit", () => {
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
});

/** A temp folder removed when the test process exits, pass or fail. */
export function tempDir(prefix = "plugin-profiles-") {
  const dir = mkdtempSync(join(tmpdir(), prefix));
  dirs.push(dir);
  return dir;
}

/** Writes each {relative path: text or JSON value} under root. */
export function writeTree(root, files) {
  for (const [rel, body] of Object.entries(files)) {
    const path = join(root, rel);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, typeof body === "string" ? body : `${JSON.stringify(body, null, 2)}\n`);
  }
  return root;
}
