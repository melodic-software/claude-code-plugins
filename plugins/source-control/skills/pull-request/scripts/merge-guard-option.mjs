// GENERATED from lib/merge-guard-option.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { realpathSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./plugin-options.mjs";

const KEY = "merge_guard_ignored_checks";
let guardrails = { pluginId: null, name: "guardrails", userSettings: null };
for (let dir = dirname(realpathSync.native(fileURLToPath(import.meta.url))); ; dir = dirname(dir)) {
  const own = resolveInstall(dir);
  if (own.pluginId !== null) {
    guardrails = { ...guardrails, pluginId: `guardrails@${own.pluginId.slice(own.name.length + 1)}`, userSettings: own.userSettings };
    break;
  }
  if (dirname(dir) === dir) break;
}
try {
  const options = readOperatorOptions(guardrails, managedSettingsFiles(), [KEY]);
  if (!Object.hasOwn(options, KEY)) process.exit(1);
  process.stdout.write(options[KEY].value);
} catch (error) {
  process.stderr.write(`${error instanceof OptionsError ? error.message : error.stack}\n`);
  process.exit(3);
}
