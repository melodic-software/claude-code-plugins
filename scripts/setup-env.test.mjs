// Suite for scripts/setup-env.sh. Every tool it installs with (python, npm,
// node, sudo) is a stub on PATH that logs its arguments, so the suite checks
// what the script asks for, not what the network returns.
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, test } from "node:test";

const script = join(import.meta.dirname, "setup-env.sh");
const which = (tool) =>
  spawnSync("sh", ["-c", `command -v ${tool}`], {
    encoding: "utf8",
  }).stdout.trim();
const bash = which("bash");
let dir;
let root;
let stubs;
let log;

function stub(name, body) {
  const file = join(stubs, name);
  writeFileSync(
    file,
    `#!/usr/bin/env bash\necho "${name} $*" >>"${log}"\n${body}\n`,
  );
  chmodSync(file, 0o755);
}

function run(args = [], env = {}) {
  writeFileSync(log, "");
  const result = spawnSync(bash, [script, "--root", root, ...args], {
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${stubs}:${process.env.PATH}`,
      GITHUB_PATH: "",
      SETUP_ENV_PLAYWRIGHT: "",
      ...env,
    },
  });
  return {
    ...result,
    calls: readFileSync(log, "utf8")
      .split("\n")
      .filter((c) => c && !/ -c /.test(c)),
  };
}

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "setup-env-"));
  root = join(dir, "repo");
  stubs = join(dir, "stubs");
  log = join(dir, "calls.log");
  mkdirSync(join(root, ".github/standards/runner-policy"), { recursive: true });
  mkdirSync(stubs);
  // A version no real interpreter has, so only the stub can match it.
  writeFileSync(join(root, ".python-version"), "3.99\n");
  writeFileSync(
    join(root, ".github/requirements-ci.txt"),
    "pytest==9.1.1 --hash=sha256:aa\n",
  );
  writeFileSync(join(root, "package-lock.json"), '{"v":1}\n');
  writeFileSync(
    join(root, ".github/standards/runner-policy/package-lock.json"),
    '{"v":2}\n',
  );
  stub(
    "python3.99",
    `if [ "$2" = -m ] && [ "$3" = venv ]; then
  mkdir -p "$5/bin"
  printf '#!/usr/bin/env bash\\necho "venv-python $*" >>"${log}"\\n' >"$5/bin/python"
  chmod +x "$5/bin/python"
fi`,
  );
  stub("npm", 'mkdir -p "$3/node_modules"');
  stub("node", "");
  stub("sudo", "exit 1");
  shellcheck("0.11.0");
});

// A shellcheck on PATH that reports VERSION and logs nothing.
function shellcheck(version) {
  writeFileSync(
    join(stubs, "shellcheck"),
    `#!/usr/bin/env bash\necho "version: ${version}"\n`,
  );
  chmodSync(join(stubs, "shellcheck"), 0o755);
}

const pin = readFileSync(script, "utf8").match(
  /shellcheck_sha256=([0-9a-f]{64})/,
)?.[1];

// curl writes a release tarball holding a shellcheck that reports VERSION.
function release(version) {
  const src = join(dir, "release", `shellcheck-v${version}`);
  mkdirSync(src, { recursive: true });
  writeFileSync(
    join(src, "shellcheck"),
    `#!/usr/bin/env bash\necho "version: ${version}"\n`,
  );
  chmodSync(join(src, "shellcheck"), 0o755);
  const tarball = join(dir, "release.tar.gz");
  spawnSync("tar", [
    "-czf",
    tarball,
    "-C",
    join(dir, "release"),
    `shellcheck-v${version}`,
  ]);
  stub("curl", `cp "${tarball}" "\${@: -1}"`);
}

afterEach(() => rmSync(dir, { recursive: true, force: true }));

test("a first run installs the pinned wheels into a venv and runs npm ci in both lock dirs", () => {
  const r = run();
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.calls, [
    `python3.99 -I -m venv --clear ${root}/.work/venv`,
    "venv-python -I -m pip install --quiet --only-binary=:all: --require-hashes --requirement .github/requirements-ci.txt",
    "npm ci --prefix .",
    "npm ci --prefix .github/standards/runner-policy",
  ]);
});

test("a second run with unchanged lock files installs nothing", () => {
  run();
  const r = run();
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.calls, []);
});

test("a changed lock file reinstalls only what it pins", () => {
  run();
  writeFileSync(join(root, "package-lock.json"), '{"v":3}\n');
  const r = run();
  assert.deepEqual(r.calls, ["npm ci --prefix ."]);
});

test("Chromium is installed only when asked, by flag or by env", () => {
  run();
  assert.ok(!run().calls.some((c) => c.startsWith("node ")));
  assert.deepEqual(run(["--playwright"]).calls, [
    "sudo -n true",
    "node node_modules/playwright/cli.js install chromium",
  ]);
  assert.deepEqual(
    run([], { SETUP_ENV_PLAYWRIGHT: "1" }).calls.at(-1),
    "node node_modules/playwright/cli.js install chromium",
  );
});

test("with sudo, Chromium comes with its system libraries", () => {
  run();
  stub("sudo", "exit 0");
  assert.equal(
    run(["--playwright"]).calls.at(-1),
    "node node_modules/playwright/cli.js install --with-deps chromium",
  );
});

test("under Actions the venv and node_modules/.bin go on GITHUB_PATH", () => {
  const pathFile = join(dir, "github-path");
  writeFileSync(pathFile, "");
  assert.equal(run([], { GITHUB_PATH: pathFile }).status, 0);
  assert.equal(
    readFileSync(pathFile, "utf8"),
    `${root}/.work/venv/bin\n${root}/node_modules/.bin\n`,
  );
});

test("no matching Python and no uv fails without installing", () => {
  rmSync(join(stubs, "python3.99"));
  // Only the stubs and the coreutils the script reads with, so no real python or uv resolves.
  const tools = join(dir, "tools");
  mkdirSync(tools);
  for (const tool of ["cat", "cut", "tr", "sha256sum"])
    symlinkSync(which(tool), join(tools, tool));
  const r = run([], { PATH: `${stubs}:${tools}` });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /no Python 3\.99/);
  assert.deepEqual(r.calls, []);
});

test("an unknown argument is a usage error", () => {
  const r = run(["--bogus"]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /unknown argument: --bogus/);
});

test("a changed requirements file rebuilds the venv", () => {
  run();
  writeFileSync(
    join(root, ".github/requirements-ci.txt"),
    "pytest==9.1.2 --hash=sha256:bb\n",
  );
  const r = run();
  assert.deepEqual(r.calls, [
    `python3.99 -I -m venv --clear ${root}/.work/venv`,
    "venv-python -I -m pip install --quiet --only-binary=:all: --require-hashes --requirement .github/requirements-ci.txt",
  ]);
});

test("SETUP_ENV_VENV places the venv", () => {
  const venv = join(dir, "elsewhere");
  const r = run([], { SETUP_ENV_VENV: venv });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.calls[0], `python3.99 -I -m venv --clear ${venv}`);
});

test("with no matching Python, uv makes the venv", () => {
  rmSync(join(stubs, "python3.99"));
  stub(
    "uv",
    `mkdir -p "\${@: -1}/bin"
printf '#!/usr/bin/env bash\\necho "venv-python $*" >>"${log}"\\n' >"\${@: -1}/bin/python"
chmod +x "\${@: -1}/bin/python"`,
  );
  const tools = join(dir, "tools");
  mkdirSync(tools);
  for (const tool of [
    "bash",
    "cat",
    "cut",
    "tr",
    "sha256sum",
    "mkdir",
    "chmod",
  ])
    symlinkSync(which(tool), join(tools, tool));
  const r = run([], { PATH: `${stubs}:${tools}` });
  assert.equal(
    r.calls[0],
    `uv venv --quiet --seed --clear --python 3.99 ${root}/.work/venv`,
  );
  assert.equal(
    r.calls[1],
    "venv-python -I -m pip install --quiet --only-binary=:all: --require-hashes --requirement .github/requirements-ci.txt",
  );
});

test("a relative --root resolves against the caller's directory", () => {
  const pathFile = join(dir, "github-path");
  writeFileSync(pathFile, "");
  writeFileSync(log, "");
  const r = spawnSync(bash, [script, "--root", "repo"], {
    cwd: dir,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${stubs}:${process.env.PATH}`,
      GITHUB_PATH: pathFile,
      SETUP_ENV_PLAYWRIGHT: "",
    },
  });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(
    readFileSync(pathFile, "utf8"),
    `${root}/.work/venv/bin\n${root}/node_modules/.bin\n`,
  );
});

test("an older shellcheck on PATH gets the pinned release in the venv's bin", () => {
  shellcheck("0.9.0");
  stub("uname", 'echo "Linux x86_64"');
  release("0.11.0");
  // The fixture tarball cannot match the real release's checksum, so the
  // checksum tool reports the pin for it.
  stub(
    "sha256sum",
    `case "$1" in *.tar.gz) echo "${pin}  $1" ;; *) ${which("sha256sum")} "$@" ;; esac`,
  );
  const r = run();
  assert.equal(r.status, 0, r.stderr);
  assert.ok(pin, "setup-env.sh pins a shellcheck_sha256");
  assert.ok(
    r.calls.some((c) =>
      c.startsWith(
        "curl -fsSL --retry 3 https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.gz -o ",
      ),
    ),
    r.calls.join("\n"),
  );
  const installed = spawnSync(
    join(root, ".work/venv/bin/shellcheck"),
    ["--version"],
    { encoding: "utf8" },
  );
  assert.equal(installed.stdout.trim(), "version: 0.11.0");
  // The installed copy satisfies the next run.
  assert.ok(!run().calls.some((c) => c.startsWith("curl ")));
});

test("a shellcheck download that fails its checksum installs nothing", () => {
  shellcheck("0.9.0");
  stub("uname", 'echo "Linux x86_64"');
  release("0.11.0");
  const r = run();
  assert.equal(r.status, 1);
  assert.match(r.stderr, /checksum/);
  assert.equal(
    spawnSync("test", ["-e", join(root, ".work/venv/bin/shellcheck")]).status,
    1,
  );
});

test("off Linux x86_64 an older shellcheck is reported, not replaced", () => {
  shellcheck("0.9.0");
  stub("uname", 'echo "Darwin arm64"');
  const r = run();
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /no shellcheck 0\.11\.0/);
  assert.ok(!r.calls.some((c) => c.startsWith("curl ")));
});
