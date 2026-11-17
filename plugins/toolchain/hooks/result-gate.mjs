import { readFileSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isClean, lastSeen, remember, repository, results, treeHash } from "../lib/tree-result.mjs";
import { managedSettingsFiles, readOperatorOptions, resolveInstall } from "./plugin-options.mjs";

const KEY = "turn_end_result_gate";
const MODES = ["off", "advisory", "enforce"];
const DEFAULT_MODE = "advisory";

function mode() {
  try {
    const pluginRoot = resolve(dirname(realpathSync.native(fileURLToPath(import.meta.url))), "..");
    const value = readOperatorOptions(resolveInstall(pluginRoot), managedSettingsFiles(), [KEY])[KEY]?.value;
    return MODES.includes(value) ? value : DEFAULT_MODE;
  } catch {
    return DEFAULT_MODE;
  }
}

function emit(object) {
  process.stdout.write(`${JSON.stringify(object)}\n`);
}

function main() {
  let payload;
  try {
    payload = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return;
  }
  if (payload === null || typeof payload !== "object" || payload.hook_event_name !== "Stop") return;
  const gate = mode();
  if (gate === "off") return;

  let repo;
  let tree;
  let found;
  try {
    repo = repository(typeof payload.cwd === "string" && payload.cwd ? payload.cwd : process.cwd());
    if (isClean(repo)) return;
    tree = treeHash(repo);
    found = results(repo, tree);
  } catch {
    return;
  }
  const seen = [tree, ...found.map((entry) => `${entry.skill}=${entry.line}`)].join("\t");
  const session = typeof payload.session_id === "string" ? payload.session_id : "";
  if (lastSeen(repo, session) === seen) return;
  remember(repo, session, seen);

  const short = tree.slice(0, 12);
  if (found.length === 0) {
    emit({
      systemMessage: `toolchain: no /toolchain:check or /toolchain:lint result is recorded for this tree (${short}). Run /toolchain:check to verify the changes.`,
    });
    return;
  }
  const notPassing = found.filter((entry) => entry.verdict !== "PASS");
  if (notPassing.length === 0) return;
  const named = notPassing.map((entry) =>
    entry.verdict === null ? `${entry.skill}: unreadable record` : `${entry.skill}: ${entry.line}`,
  );
  const message = `toolchain: the recorded result for this tree (${short}) is not a pass. ${named.join("; ")}`;
  const block =
    gate === "enforce" && notPassing.some((entry) => entry.verdict === "FAIL") && payload.stop_hook_active !== true;
  emit({
    systemMessage: message,
    ...(block && {
      decision: "block",
      reason: `${message}. Fix the failure and run the skill again, or say why it stays failing, before ending the turn.`,
    }),
  });
}

main();
