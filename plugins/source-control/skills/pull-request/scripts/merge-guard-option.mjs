// GENERATED from lib/merge-guard-option.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Prints the guardrails `merge_guard_ignored_checks` value the operator configured, for
// merge-readiness.sh run as a command by the source-control pull-request skill. That run is outside
// the guardrails hook environment, which is where Claude Code delivers the value as
// CLAUDE_PLUGIN_OPTION_MERGE_GUARD_IGNORED_CHECKS, so it reads the same pluginConfigs entry from the
// operator's settings (channel F of
// https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/hook-config-delivery/README.md,
// through plugin-options.mjs):
// the merge guard and the skill then judge failed checks against one value.
// The entry read is guardrails@<marketplace>, the marketplace this copy was installed from; an
// install outside the plugin cache reads only managed settings, matched by the name guardrails.
//   node merge-guard-option.mjs
//     exit 0, the value on stdout: configured
//     exit 1: not configured, so the caller applies the option's default
//     exit 3, the reason on stderr: a settings source could not be read
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
