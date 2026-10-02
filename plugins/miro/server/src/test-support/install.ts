import { cpSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { installDir } from "../launcher.ts";

export const SERVER_DIR = fileURLToPath(new URL("../..", import.meta.url));
export const LAUNCH = join(SERVER_DIR, "src", "launch.ts");

export function tempDataDir(): { dataDir: string; cleanup: () => void } {
  const dataDir = mkdtempSync(join(tmpdir(), "miro-launch-"));
  return { dataDir, cleanup: () => rmSync(dataDir, { recursive: true, force: true }) };
}

// Stands in for a finished `npm ci`: the development install already holds every runtime
// dependency, so the launcher sees a complete install and never runs npm.
export function seedInstall(dataDir: string): string {
  const target = installDir(dataDir);
  mkdirSync(target, { recursive: true });
  cpSync(join(SERVER_DIR, "package.json"), join(target, "package.json"));
  symlinkSync(join(SERVER_DIR, "node_modules"), join(target, "node_modules"), "junction");
  return target;
}
