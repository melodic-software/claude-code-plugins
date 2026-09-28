import assert from "node:assert/strict";
import { resolveBash } from "./exec-bash.mjs";

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
