import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { failureLine, optionGateOpen, parseLaunchArgs, resolveBash } from "./exec-bash.mjs";

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
assert.match(bad.error, /usage:/);
const none = parseLaunchArgs([]);
assert.match(none.error, /usage:/);

// Failure lines: one line under 240 characters, the script and the consequence first.
const winScript = "C:\\Users\\u\\.claude\\plugins\\guardrails\\hooks\\run-guards.sh";
const posixScript = "/home/u/.claude/plugins/guardrails/hooks/run-guards.sh";
const runtimeLines = {
  "no-bash win32": failureLine("no-bash", { script: winScript, platform: "win32" }),
  "no-bash linux": failureLine("no-bash", { script: posixScript, platform: "linux" }),
  "spawn win32": failureLine("spawn", {
    script: winScript,
    bash: gitBin,
    platform: "win32",
    detail: `spawn ${gitBin} ENOENT`,
  }),
};
for (const [label, line] of Object.entries(runtimeLines)) {
  assert.match(line, /^exec-bash: run-guards\.sh did not run, so this hook enforces nothing: /, label);
}
const allLines = [
  ...Object.values(runtimeLines),
  failureLine("signal", { script: posixScript, detail: "SIGKILL" }),
  failureLine("usage", { detail: none.error }),
  failureLine("usage", { detail: bad.error }),
  failureLine("spawn", { script: "x.sh", bash: "/bin/bash", detail: "line one\nline two\r\n  three" }),
];
for (const line of allLines) {
  assert.doesNotMatch(line, /[\r\n]/, line);
  assert.ok(line.length < 240, `${line.length} characters: ${line}`);
  assert.ok(line.startsWith("exec-bash: "), line);
}
assert.match(runtimeLines["no-bash win32"], /CLAUDE_CODE_GIT_BASH_PATH/);
assert.match(runtimeLines["no-bash win32"], /System32\\bash\.exe is the WSL relay/);
assert.match(runtimeLines["no-bash linux"], /put bash on PATH/);
assert.doesNotMatch(runtimeLines["no-bash linux"], /CLAUDE_CODE_GIT_BASH_PATH/);
assert.match(runtimeLines["spawn win32"], /could not start C:\\Program Files\\Git\\bin\\bash\.exe: spawn .* ENOENT$/);
assert.match(failureLine("spawn", { script: "x.sh", bash: "b", detail: "d" }), /enforces nothing/);
assert.match(failureLine("signal", { script: posixScript, detail: "SIGKILL" }), /^exec-bash: run-guards\.sh was killed by SIGKILL /);
assert.match(failureLine("usage", { detail: none.error }), /launcher itself was called wrongly.*usage: node exec-bash\.mjs/);

// Live failures: exit 1, nothing on stdout, and exactly one stderr line.
const launcher = fileURLToPath(new URL("./exec-bash.mjs", import.meta.url));
function runLauncher(args, env, nodeArgs = []) {
  const run = spawnSync(process.execPath, [...nodeArgs, launcher, ...args], {
    env: { SystemRoot: process.env.SystemRoot, ...env },
    encoding: "utf8",
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(run.stdout, "");
  assert.equal(run.stderr.split("\n").length, 2, run.stderr);
  return run.stderr;
}

// An empty env on a stubbed win32 leaves no candidate, so no bash resolves on any host.
const failRoot = mkdtempSync(path.join(tmpdir(), "exec-bash-fail-"));
try {
  const stub = path.join(failRoot, "win32-stub.mjs");
  writeFileSync(stub, 'Object.defineProperty(process, "platform", { value: "win32" });\n');
  assert.match(
    runLauncher(["x.sh"], {}, ["--import", pathToFileURL(stub).href]),
    /^exec-bash: x\.sh did not run, so this hook enforces nothing: no bash found\. Set CLAUDE_CODE_GIT_BASH_PATH .*WSL relay.*\n$/,
  );
  assert.match(runLauncher([], {}), /^exec-bash: the launcher itself was called wrongly, so no hook ran: usage: /);

  if (process.platform !== "win32") {
    // A bash that is a file but not executable resolves, then fails to spawn.
    mkdirSync(path.join(failRoot, "bin"));
    const noexec = path.join(failRoot, "bin", "bash");
    writeFileSync(noexec, "#!/bin/sh\n");
    chmodSync(noexec, 0o644);
    const spawnErr = runLauncher(["hook.sh"], { PATH: path.join(failRoot, "bin") });
    assert.ok(
      spawnErr.startsWith(`exec-bash: hook.sh did not run, so this hook enforces nothing: could not start ${noexec}: `),
      spawnErr,
    );
    assert.match(spawnErr, /EACCES/);

    // A child killed by a signal has no exit code; the line names the signal.
    const killed = path.join(failRoot, "killed.sh");
    writeFileSync(killed, "kill -KILL $$\n");
    assert.match(
      runLauncher([killed], { PATH: process.env.PATH }),
      /^exec-bash: killed\.sh was killed by SIGKILL before it finished, so it enforced nothing for this call\.\n$/,
    );
  }
} finally {
  rmSync(failRoot, { recursive: true, force: true });
}

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

// A launch through a symlinked path runs the script and forwards its exit code.
// Node realpaths the main entry, so a path comparison that skips realpath never
// reaches main() and the hook exits 0 with no output.
if (process.platform !== "win32") {
  const root = mkdtempSync(path.join(tmpdir(), "exec-bash-link-"));
  try {
    symlinkSync(path.dirname(launcher), path.join(root, "link"), "dir");
    const script = path.join(root, "guard.sh");
    writeFileSync(script, "echo guard-ran\nexit 2\n");
    const run = spawnSync(process.execPath, [path.join(root, "link", "exec-bash.mjs"), script], {
      env: process.env,
      encoding: "utf8",
    });
    assert.equal(run.stdout, "guard-ran\n", `the script did not run: ${run.stderr}`);
    assert.equal(run.status, 2, run.stderr);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
