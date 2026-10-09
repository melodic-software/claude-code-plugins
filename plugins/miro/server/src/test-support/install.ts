import { cpSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { installDir } from "../launcher.ts";

export const SERVER_DIR = fileURLToPath(new URL("../..", import.meta.url));
export const LAUNCH = join(SERVER_DIR, "src", "launch.ts");

export function tempDataDir(): { dataDir: string; cleanup: () => void } {
  const dataDir = mkdtempSync(join(tmpdir(), "miro-launch-"));
  return {
    dataDir,
    cleanup: () => {
      // seedInstall links node_modules to the real one: drop the link itself first so a
      // recursive delete can never walk into the development install.
      try {
        unlinkSync(join(installDir(dataDir), "node_modules"));
      } catch {
        // no link was made, or it is already gone
      }
      rmSync(dataDir, { recursive: true, force: true });
    },
  };
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
