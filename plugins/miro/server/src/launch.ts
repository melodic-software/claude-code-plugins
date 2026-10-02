import { launch } from "./launcher.ts";
import { writeStderr } from "./stderr.ts";

try {
  await launch();
} catch (error) {
  writeStderr(`miro MCP server cannot start: ${(error as Error).message}`);
  process.exit(1);
}
