import { pathToFileURL } from "node:url";

export function runAsScript(metaUrl, label, run) {
  if (!process.argv[1] || metaUrl !== pathToFileURL(process.argv[1]).href) return;
  run().then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::${label} failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
