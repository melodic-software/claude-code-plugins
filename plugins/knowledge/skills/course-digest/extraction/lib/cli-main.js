import { pathToFileURL } from "node:url";

// True only when this process was started with the caller's file as the
// entrypoint. Importing the CLI must not parse argv or run main.
export function invokedAsCli(moduleUrl) {
  const entry = process.argv[1];
  return Boolean(entry) && moduleUrl === pathToFileURL(entry).href;
}
