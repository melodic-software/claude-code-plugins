import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

// True only when this process was started with the caller's file as the
// entrypoint. Importing the CLI must not parse argv or run main. Real paths
// are compared because Node resolves import.meta.url through symlinks while
// argv[1] keeps the path as typed, so a symlinked plugin root would otherwise
// skip main and exit 0 without doing anything.
export function invokedAsCli(moduleUrl) {
  const entry = process.argv[1];
  if (!entry) return false;
  try {
    return realpathSync(entry) === realpathSync(fileURLToPath(moduleUrl));
  } catch {
    return false;
  }
}
