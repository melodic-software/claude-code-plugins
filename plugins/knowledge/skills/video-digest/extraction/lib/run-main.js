import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr } from "@melodic/video-digestion/shared/terminal";

/**
 * Run an async CLI when the calling module is the process entrypoint: its
 * resolved code becomes the exit code, and a thrown error prints its message
 * to stderr and exits 1.
 *
 * @param {string} moduleUrl - the caller's `import.meta.url`
 * @param {(argv: string[]) => Promise<number>} cli
 * @returns {void}
 */
export function runMain(moduleUrl, cli) {
  if (!isMainModule(moduleUrl)) return;
  cli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
