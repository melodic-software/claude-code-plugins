import { launch } from "./launcher.ts";
import { writeStderr } from "./stderr.ts";

// exitCode, not exit(): the process ends once stderr has flushed, so a long diagnostic on a
// pipe arrives whole. A failed launch leaves nothing holding the event loop open.
try {
  await launch();
} catch (error) {
  writeStderr(`miro MCP server cannot start: ${(error as Error).message}`);
  process.exitCode = 1;
}
