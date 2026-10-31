// Stop hook: warn when a turn ends on a tree whose recorded /toolchain:check or /toolchain:lint
// result is not a pass.
//
// It reads the Overall line those skills recorded for the current tree hash
// (../lib/tree-result.mjs) and never runs a build, test or lint command. A clean work tree gives
// no warning: nothing has changed for a check to cover. Neither does a turn that changed no file
// and recorded no result: the hook keeps what it saw at the session's previous turn end and stays
// quiet when the tree and its records are the same.
//
// Mode, the turn_end_result_gate userConfig option:
//   off       print nothing
//   advisory  (default) exit 0 with a systemMessage naming each result that is not PASS, or
//             saying no result is recorded for this tree; never blocks
//   enforce   as advisory, and a recorded FAIL also blocks the stop once (decision "block");
//             INCOMPLETE, STOPPED, no record, an unreadable record or a missing tool never block
//
// The option is read from managed and user settings only (plugin-options.mjs), never from the
// CLAUDE_PLUGIN_OPTION_* environment mirror, so a watched repository's settings env block cannot
// turn the gate off. Any error reading it, the payload or the repository fails open: the stop goes
// ahead with nothing printed.

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
  // Same tree and same records as this session's previous turn end: the turn changed no file and
  // recorded no result, so there is nothing new to say.
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
  const failed = notPassing.some((entry) => entry.verdict === "FAIL");
  if (gate === "enforce" && failed && payload.stop_hook_active !== true) {
    emit({
      systemMessage: message,
      decision: "block",
      reason: `${message}. Fix the failure and run the skill again, or say why it stays failing, before ending the turn.`,
    });
    return;
  }
  emit({ systemMessage: message });
}

main();
