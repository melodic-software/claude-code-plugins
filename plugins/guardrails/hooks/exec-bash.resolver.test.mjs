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

function existsIn(...files) {
  const set = new Set(files.map(key));
  return (p) => set.has(key(p));
}

// PATH comes before the fixed /bin and /usr/bin candidates (a Homebrew bash wins).
assert.equal(
  resolveBash(
    { PATH: "/opt/homebrew/bin:/usr/bin" },
    "linux",
    existsIn("/opt/homebrew/bin/bash", "/usr/bin/bash"),
  ),
  "/opt/homebrew/bin/bash",
);

// Empty and relative PATH entries never reach exists.
const probed = [];
const skipped = resolveBash({ PATH: ":.:bin:/opt/x::../y" }, "linux", (p) => {
  probed.push(p);
  return p === "/opt/x/bash";
});
assert.equal(skipped, "/opt/x/bash");
assert.deepEqual(probed, ["/opt/x/bash"]);

// No bash on PATH falls back to /bin/bash, then /usr/bin/bash.
assert.equal(
  resolveBash({ PATH: "/opt/none" }, "linux", existsIn("/bin/bash", "/usr/bin/bash")),
  "/bin/bash",
);
assert.equal(resolveBash({ PATH: "/opt/none" }, "linux", existsIn("/usr/bin/bash")), "/usr/bin/bash");

// win32: bash.exe on PATH is found when no Git root exists (Scoop layout).
const scoop = "D:\\scoop\\apps\\git\\current\\bin\\bash.exe";
assert.equal(
  key(resolveBash({ PATH: "C:\\Tools;D:\\scoop\\apps\\git\\current\\bin" }, "win32", existsIn(scoop))),
  key(scoop),
);

// win32: a Git root beats a PATH hit.
assert.equal(
  key(
    resolveBash(
      { ProgramFiles: "C:\\Program Files", PATH: "D:\\scoop\\apps\\git\\current\\bin" },
      "win32",
      existsIn(gitBin, scoop),
    ),
  ),
  key(gitBin),
);

// win32: the WSL relay is rejected when PATH supplies it; the next entry wins.
const tools = "D:\\tools\\Git\\bin\\bash.exe";
assert.equal(
  key(
    resolveBash(
      { PATH: "C:\\Windows\\System32;D:\\tools\\Git\\bin" },
      "win32",
      existsIn(relay, tools),
    ),
  ),
  key(tools),
);
