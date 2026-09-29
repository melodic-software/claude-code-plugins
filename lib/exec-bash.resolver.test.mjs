import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
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
assert.equal(
  resolveBash({ PATH: ":.:bin:" }, "linux", existsIn("bash", "./bash", "bin/bash")),
  null,
);

// No bash on PATH falls back to /bin/bash, then /usr/bin/bash.
assert.equal(
  resolveBash({ PATH: "/opt/none" }, "linux", existsIn("/bin/bash", "/usr/bin/bash")),
  "/bin/bash",
);
assert.equal(resolveBash({ PATH: "/opt/none" }, "linux", existsIn("/usr/bin/bash")), "/usr/bin/bash");
assert.equal(resolveBash({ PATH: "/opt/none" }, "linux", () => false), null);

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

// win32: CLAUDE_CODE_GIT_BASH_PATH beats a PATH hit.
assert.equal(
  key(
    resolveBash(
      { CLAUDE_CODE_GIT_BASH_PATH: gitUsr, PATH: "D:\\scoop\\apps\\git\\current\\bin" },
      "win32",
      existsIn(gitUsr, scoop),
    ),
  ),
  key(gitUsr),
);

// win32: the WSL relay is rejected when PATH supplies it; the next entry wins.
const storeStub = "C:\\Users\\u\\AppData\\Local\\Microsoft\\WindowsApps\\bash.exe";
const sysnative = "C:\\Windows\\Sysnative\\bash.exe";
const tools = "D:\\tools\\Git\\bin\\bash.exe";
assert.equal(
  key(
    resolveBash(
      {
        PATH: [
          "C:\\Windows\\System32",
          "C:\\Windows\\Sysnative",
          "C:\\Users\\u\\AppData\\Local\\Microsoft\\WindowsApps",
          "D:\\tools\\Git\\bin",
        ].join(";"),
      },
      "win32",
      existsIn(relay, sysnative, storeStub, tools),
    ),
  ),
  key(tools),
);
assert.equal(
  resolveBash({ PATH: "C:\\Windows\\System32" }, "win32", existsIn(relay)),
  null,
);

// win32: a mixed-case Path variable works, and so do quoted and relative entries.
assert.equal(key(resolveBash({ Path: "D:\\scoop\\apps\\git\\current\\bin" }, "win32", existsIn(scoop))), key(scoop));
assert.equal(
  key(resolveBash({ PATH: '"D:\\scoop\\apps\\git\\current\\bin";' }, "win32", existsIn(scoop))),
  key(scoop),
);
assert.equal(resolveBash({ PATH: ".;bin;;" }, "win32", existsIn("bash.exe", ".\\bash.exe", "bin\\bash.exe")), null);
assert.equal(resolveBash({}, "win32", () => false), null);

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

// Live launch: PATH's bash runs the script, and a directory named bash is skipped.
if (process.platform !== "win32") {
  const root = mkdtempSync(path.join(tmpdir(), "exec-bash-path-"));
  try {
    mkdirSync(path.join(root, "dir", "bash"), { recursive: true });
    mkdirSync(path.join(root, "bin"));
    const wrapper = path.join(root, "bin", "bash");
    writeFileSync(wrapper, '#!/bin/sh\necho path-bash\nexec /bin/bash "$@"\n');
    chmodSync(wrapper, 0o755);
    const script = path.join(root, "hook.sh");
    writeFileSync(script, "echo hook-ran\n");
    const run = spawnSync(process.execPath, [fileURLToPath(new URL("./exec-bash.mjs", import.meta.url)), script], {
      env: { ...process.env, PATH: `${path.join(root, "dir")}:${path.join(root, "bin")}:${process.env.PATH}` },
      encoding: "utf8",
    });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, "path-bash\nhook-ran\n");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
