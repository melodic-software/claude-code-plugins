// Runs the action's "Install subprocess isolation" script against stand-ins for
// sudo, apt-get, apt-cache and dpkg-deb, on a PATH that holds no real bwrap or
// socat, so each case controls which package source answers.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";

const ACTION = new URL("./action.yml", import.meta.url);
const FAIL_CLOSED = "::error::bubblewrap or socat is not installed; Claude Code cannot scrub its subprocess environment";

function installScript() {
  const lines = readFileSync(ACTION, "utf8").split("\n");
  const name = lines.findIndex((line) => line.trim() === "- name: Install subprocess isolation");
  assert.notEqual(name, -1, "action.yml has the install step");
  const start = lines.findIndex((line, i) => i > name && /^\s+run: \|$/.test(line));
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

const TOOLS = ["bash", "mkdir", "rm", "awk", "sha256sum", "cut", "timeout", "cat", "grep", "touch", "chmod", "cp"];

const sh = (body) => `#!/bin/bash\n${body}\n`;

// apt-get stand-in. FAKE_APT: `down` fails every call that needs the mirror; `lists` installs without
// an index refresh; `stale` installs only after `update`. Installing writes bwrap
// and socat into the PATH directory, and the two debs into Dir::Cache::archives.
const APT_GET = sh(`
echo "apt-get $*" >>"$FAKE_LOG"
args=" $* "
if [[ $args == *" --no-download "* ]]; then
  [ "$FAKE_LOCAL" = ok ] || exit 100
elif [ "$FAKE_APT" = down ]; then
  exit 100
elif [[ $args == *" update "* ]]; then
  touch "$FAKE_STATE/updated"; exit 0
elif [ "$FAKE_APT" = stale ] && [ ! -e "$FAKE_STATE/updated" ]; then
  exit 100
fi
if [[ $args =~ Dir::Cache::archives=([^ ]*) ]]; then
  printf 'Package: bubblewrap\\n' >"\${BASH_REMATCH[1]}bubblewrap.deb"
  printf 'Package: socat\\n' >"\${BASH_REMATCH[1]}socat.deb"
fi
for tool in bwrap socat; do printf '#!/bin/bash\\n' >"$FAKE_BIN/$tool"; chmod +x "$FAKE_BIN/$tool"; done
`);

// The image's package lists: every package's candidate is 1.0, with the SHA-256
// of the genuine deb the test wrote.
const APT_CACHE = sh(`
case "$1" in
  policy) echo "  Candidate: 1.0" ;;
  show) pkg="\${2%%=*}"; [ -f "$FAKE_STATE/index-$pkg" ] && echo "SHA256: $(cat "$FAKE_STATE/index-$pkg")" ;;
esac
`);

const DPKG_DEB = sh(`awk -F': ' '/^Package:/ {print $2}' "$2"`);

function run({ apt, local = "ok", cached = {}, index = {}, preinstalled = [] }) {
  const root = tempDir("runner-isolation-");
  const bin = path.join(root, "bin");
  const state = path.join(root, "state");
  const temp = path.join(root, "temp");
  for (const dir of [bin, state, path.join(temp, "isolation-debs")]) mkdirSync(dir, { recursive: true });
  for (const tool of TOOLS) symlinkSync(execFileSync("bash", ["-c", `command -v ${tool}`], { encoding: "utf8" }).trim(), path.join(bin, tool));
  const stubs = { sudo: sh('exec "$@"'), sleep: sh(":"), sysctl: sh(":"), "apt-get": APT_GET, "apt-cache": APT_CACHE, "dpkg-deb": DPKG_DEB };
  for (const tool of preinstalled) stubs[tool] = sh(":");
  for (const [name, body] of Object.entries(stubs)) {
    writeFileSync(path.join(bin, name), body);
    chmodSync(path.join(bin, name), 0o755);
  }
  for (const [file, content] of Object.entries(cached)) writeFileSync(path.join(temp, "isolation-debs", file), content);
  for (const [pkg, content] of Object.entries(index)) {
    const sum = execFileSync("sha256sum", { input: content, encoding: "utf8" }).split(" ")[0];
    writeFileSync(path.join(state, `index-${pkg}`), sum);
  }
  const output = path.join(root, "output");
  const log = path.join(root, "log");
  writeFileSync(output, "");
  writeFileSync(log, "");
  const result = spawnSync(path.join(bin, "bash"), ["-e", "-o", "pipefail", "-c", installScript()], {
    encoding: "utf8",
    env: { PATH: bin, RUNNER_TEMP: temp, GITHUB_OUTPUT: output, FAKE_LOG: log, FAKE_BIN: bin, FAKE_STATE: state, FAKE_APT: apt, FAKE_LOCAL: local },
  });
  return {
    status: result.status,
    stdout: result.stdout,
    calls: readFileSync(log, "utf8").trim().split("\n").filter(Boolean),
    output: readFileSync(output, "utf8"),
    installed: existsSync(path.join(bin, "bwrap")) && existsSync(path.join(bin, "socat")),
    debsDir: path.join(temp, "isolation-debs"),
    debs: readdirSync(path.join(temp, "isolation-debs")).filter((f) => f.endsWith(".deb")).sort(),
  };
}

const GENUINE = { "bubblewrap.deb": "Package: bubblewrap\n", "socat.deb": "Package: socat\n" };
const INDEX = { bubblewrap: GENUINE["bubblewrap.deb"], socat: GENUINE["socat.deb"] };

test("a verified cache hit installs offline and makes no mirror call", () => {
  const r = run({ apt: "down", cached: GENUINE, index: INDEX });
  assert.equal(r.status, 0, r.stdout);
  assert.equal(r.installed, true);
  assert.equal(r.calls.length, 1, `one apt-get call, got: ${r.calls}`);
  assert.match(r.calls[0], /install .*--no-download .*bubblewrap\.deb .*socat\.deb/);
  assert.equal(r.output, "", "a hit writes no save=true");
});

test("a cached deb that differs from the image's index is never installed", () => {
  const tampered = { ...GENUINE, "socat.deb": "Package: socat\nbackdoor\n" };
  const r = run({ apt: "lists", cached: tampered, index: INDEX });
  assert.equal(r.status, 0, r.stdout);
  assert.ok(!r.calls.some((c) => c.includes("--no-download")), `no offline install, got: ${r.calls}`);
  assert.deepEqual(r.debs, ["bubblewrap.deb", "socat.deb"], "the tampered set is replaced by apt's download");
  assert.equal(readFileSync(path.join(r.debsDir, "socat.deb"), "utf8"), "Package: socat\n");
});

test("a cached deb with an option-shaped package name is rejected", () => {
  const deb = "Package: -oFoo\n";
  const r = run({ apt: "lists", cached: { "x.deb": deb }, index: { "-oFoo": deb } });
  assert.equal(r.status, 0, r.stdout);
  assert.ok(!r.calls.some((c) => c.includes("--no-download")), `no offline install, got: ${r.calls}`);
});

test("a cache miss installs from the image's lists without an index refresh and asks to save", () => {
  const r = run({ apt: "lists" });
  assert.equal(r.status, 0, r.stdout);
  assert.equal(r.installed, true);
  assert.equal(r.calls.length, 1, `one apt-get call, got: ${r.calls}`);
  assert.ok(!r.calls[0].includes(" update"), r.calls[0]);
  assert.equal(r.output, "save=true\n");
  assert.deepEqual(r.debs, ["bubblewrap.deb", "socat.deb"]);
});

test("stale image lists fall back to update and install, and nothing is saved", () => {
  const r = run({ apt: "stale" });
  assert.equal(r.status, 0, r.stdout);
  assert.equal(r.installed, true);
  assert.equal(r.calls.length, 3, `install, update, install, got: ${r.calls}`);
  assert.match(r.calls[1], /update/);
  assert.equal(r.output, "", "debs fetched after a refresh would not verify against the image's lists");
});

test("a mirror that never answers fails closed after three attempts", () => {
  const r = run({ apt: "down" });
  assert.equal(r.status, 1);
  assert.equal(r.installed, false);
  assert.equal(r.calls.filter((c) => / update /.test(` ${c} `)).length, 3, `three update attempts, got: ${r.calls}`);
  assert.ok(r.stdout.includes(FAIL_CLOSED), r.stdout);
});

test("a cached install that fails, with the mirror down, still fails closed", () => {
  const r = run({ apt: "down", local: "no", cached: GENUINE, index: INDEX });
  assert.equal(r.status, 1);
  assert.ok(r.stdout.includes(FAIL_CLOSED), r.stdout);
});

test("bubblewrap present but socat missing fails closed", () => {
  const r = run({ apt: "down", preinstalled: ["bwrap"] });
  assert.equal(r.status, 1);
  assert.ok(r.stdout.includes(FAIL_CLOSED), r.stdout);
});

const INLINE_APT = /apt-get[^\n]*install[^\n]*\b(bubblewrap|socat)\b/;

test("the inline-apt pattern matches a known inline install line", () => {
  assert.match('timeout 180 sudo apt-get "${apt[@]}" install -y --no-install-recommends bubblewrap socat && break', INLINE_APT);
  assert.match("sudo apt-get install -y socat", INLINE_APT);
});

test("no workflow or other action installs bubblewrap or socat with its own apt block", () => {
  const github = new URL("../../", import.meta.url).pathname;
  const files = [
    ...readdirSync(path.join(github, "workflows")).filter((f) => f.endsWith(".yml")).map((f) => path.join(github, "workflows", f)),
    ...readdirSync(path.join(github, "actions"))
      .filter((d) => d !== "setup-runner-isolation" && existsSync(path.join(github, "actions", d, "action.yml")))
      .map((d) => path.join(github, "actions", d, "action.yml")),
  ];
  const inline = files.filter((f) => INLINE_APT.test(readFileSync(f, "utf8")));
  assert.deepEqual(inline.map((f) => path.relative(github, f)), []);
});
