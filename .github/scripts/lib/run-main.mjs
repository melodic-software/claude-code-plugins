// The entry tail of a lane script: run(), which resolves to the exit code,
// runs only when the importing module is the process entry point, so a test
// that imports the module runs nothing. A rejection prints `::error::<label>
// failed: <message>` and exits 1.

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
