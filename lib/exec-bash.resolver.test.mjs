import assert from "node:assert/strict";
import { optionGateOpen, parseLaunchArgs, resolveBash } from "./exec-bash.mjs";

function key(p) {
  return p.replaceAll("/", "\\").toLowerCase();
}

const gitBin = "C:\\Program Files\\Git\\bin\\bash.exe";
const gitUsr = "C:\\Program Files\\Git\\usr\\bin\\bash.exe";
const relay = "C:\\Windows\\System32\\bash.exe";
const nodeExe = "C:\\Program Files\\nodejs\\node.exe";

const present = new Set([key(relay), key(gitBin), key(gitUsr)]);
function exists(p) {
  return present.has(key(p));
}

const skippedRelay = resolveBash(
  {
    CLAUDE_CODE_GIT_BASH_PATH: relay,
    ProgramFiles: "C:\\Program Files",
  },
  "win32",
  exists,
);
assert.equal(key(skippedRelay), key(gitBin));

const named = resolveBash(
  { CLAUDE_CODE_GIT_BASH_PATH: gitUsr },
  "win32",
  exists,
);
assert.equal(key(named), key(gitUsr));

const rejected = resolveBash(
  {
    CLAUDE_CODE_GIT_BASH_PATH: nodeExe,
    ProgramFiles: "C:\\Program Files",
  },
  "win32",
  (p) => key(p) === key(nodeExe),
);
assert.equal(rejected, null);

const unix = resolveBash({}, "linux", (p) => p === "/usr/bin/bash");
assert.equal(unix, "/usr/bin/bash");

const missing = resolveBash({}, "linux", () => false);
assert.equal(missing, null);

const launched = parseLaunchArgs([
  "--require-true",
  "SESSION_EVENT_LOG_ENABLED",
  "/hooks/session-event-log.sh",
]);
assert.equal(launched.script, "/hooks/session-event-log.sh");
assert.equal(optionGateOpen(launched.gates, {}), false);
assert.equal(optionGateOpen(launched.gates, { CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED: "true" }), true);
assert.equal(optionGateOpen(launched.gates, { CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED: "false" }), false);

const defaultOn = parseLaunchArgs([
  "--run-if-unset-or-true",
  "EOL_NORMALIZER_ENABLED",
  "/hooks/eol-normalizer.sh",
  "--extra",
]);
assert.deepEqual(defaultOn.args, ["--extra"]);
assert.equal(optionGateOpen(defaultOn.gates, {}), true);
assert.equal(optionGateOpen(defaultOn.gates, { CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED: "" }), true);
assert.equal(optionGateOpen(defaultOn.gates, { CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED: "true" }), true);
assert.equal(optionGateOpen(defaultOn.gates, { CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED: "false" }), false);

const bad = parseLaunchArgs(["--require-true"]);
assert.match(bad.error, /CLAUDE_PLUGIN_OPTION_/);
const none = parseLaunchArgs([]);
assert.match(none.error, /usage:/);
