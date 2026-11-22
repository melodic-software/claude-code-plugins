import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { openBreaker, readBreaker } from "../scripts/lib/breaker.mjs";
import { loadProvider, validateProvider } from "../scripts/lib/provider.mjs";
import { configKeys, update, versionSource } from "../scripts/lib/update.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, "fixtures");
const helpDir = join(fixtures, "help-0.168.0");
const scratch = mkdtempSync(join(tmpdir(), "external-agents-update-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

const codex = loadProvider("codex");
const fakeCodex = { path: process.execPath, args: [join(fixtures, "fake-codex.mjs")], shell: false };
const DOCS = "https://learn.chatgpt.com/docs/llms.txt";
const REFERENCE = "https://learn.chatgpt.com/docs/config-file/config-reference.md";
const RELEASES = "https://api.github.com/repos/openai/codex/releases/latest";
const noon = Date.UTC(2026, 10, 21, 12, 0, 0);

const realHelp = { "--help": join(helpDir, "codex.txt"), "exec --help": join(helpDir, "exec.txt"), "exec review --help": join(helpDir, "exec-review.txt") };
const referenceText = 'key: "approval_policy",\nkey: "sandbox_mode",\nkey: "model_reasoning_effort",\n';

function web({ latest = "rust-v0.168.0", docs = 200, reference = referenceText } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, method: init.method ?? "GET" });
    if (url === RELEASES) return { ok: true, status: 200, json: async () => ({ tag_name: latest }) };
    if (url === DOCS) return { ok: docs === 200, status: docs };
    if (url === REFERENCE) {
      if (reference instanceof Error) throw reference;
      return { ok: true, status: 200, text: async () => reference };
    }
    throw new Error(`unexpected fetch ${url}`);
  };
  return { fetch, calls };
}

let count = 0;
function world(scenario = {}, { local } = {}) {
  const root = join(scratch, `w${(count += 1)}`);
  const cwd = join(root, "cwd");
  const dataDir = join(root, "data");
  mkdirSync(join(cwd, "docs", "conventions"), { recursive: true });
  mkdirSync(dataDir);
  if (local) writeFileSync(join(cwd, "docs", "conventions", "external-agents.local.yaml"), local);
  const file = join(root, "scenario.json");
  writeFileSync(file, JSON.stringify({ record: join(root, "calls.jsonl"), version: "codex-cli 0.168.0\n", help: realHelp, ...scenario }));
  return { opts: { product: "codex", cwd, dataDir, binary: fakeCodex, now: () => noon, env: { ...process.env, FAKE_SCENARIO: file } }, dataDir };
}
const lines = (got) => got.stdout.split("\n");

describe("update", () => {
  test("a present, logged-in CLI reports its version and login, caches its help per version, and checks release, docs and config keys", async () => {
    const w = world();
    const net = web();
    const got = await update({ ...w.opts, fetch: net.fetch });
    const facts = join(w.dataDir, "cli-facts", "codex", "0.168.0");
    assert.equal(got.stdout, [
      "codex: ready",
      "version: 0.168.0",
      "login: logged in",
      `cli facts: ${facts}`,
      "version check: current (latest 0.168.0, from github:openai/codex)",
      `docs index: reachable (${DOCS})`,
      "routing: due; re-read the routing pointers",
      "config keys: ok (approval_policy, sandbox_mode, model_reasoning_effort)",
      "",
    ].join("\n"));
    assert.equal(got.code, 0);
    for (const [name, source] of [["codex", "codex.txt"], ["exec", "exec.txt"], ["exec-review", "exec-review.txt"]]) {
      assert.equal(readFileSync(join(facts, `${name}.txt`), "utf8"), readFileSync(join(helpDir, source), "utf8"), name);
    }
    assert.ok(net.calls.some((c) => c.url === DOCS && c.method === "HEAD"), "the docs index is HEAD-checked");
  });

  test("a second update the same day says the daily checks already ran", async () => {
    const w = world();
    await update({ ...w.opts, fetch: web().fetch });
    const again = await update({ ...w.opts, fetch: web().fetch });
    assert.ok(lines(again).includes("version check: already checked today"), again.stdout);
    assert.ok(lines(again).includes("routing: checked earlier today"), again.stdout);
    assert.equal(again.code, 0);
  });

  test("a CLI behind its latest release gets the configured update hint", async () => {
    const w = world({}, { local: "schema: 1\ncodex:\n  update_hint: Run the dotfiles update.\n" });
    const got = await update({ ...w.opts, fetch: web({ latest: "rust-v0.171.0" }).fetch });
    assert.ok(lines(got).includes("version check: codex 0.168.0 is behind 0.171.0. Run the dotfiles update."), got.stdout);
  });

  test("a config key missing from both the help and the config reference is reported as drift", async () => {
    const w = world();
    const got = await update({ ...w.opts, fetch: web({ reference: 'key: "approval_policy",\nkey: "model_reasoning_effort",\nallowed_sandbox_modes\n' }).fetch });
    assert.equal(lines(got)[0], "codex: ready (check: config keys)");
    assert.ok(lines(got).includes(`config keys: drift: sandbox_mode is in neither the CLI help nor ${REFERENCE}`), got.stdout);
    assert.equal(got.code, 0);
  });

  test("a config reference that cannot be read leaves the keys unverified, not drifted", async () => {
    const w = world();
    const got = await update({ ...w.opts, fetch: web({ reference: new Error("getaddrinfo ENOTFOUND") }).fetch });
    assert.ok(lines(got).includes(`config keys: unverified: approval_policy, sandbox_mode, model_reasoning_effort are not in the CLI help, and ${REFERENCE} could not be read (getaddrinfo ENOTFOUND)`), got.stdout);
  });

  test("an unreachable docs index is reported", async () => {
    const w = world();
    const got = await update({ ...w.opts, fetch: web({ docs: 404 }).fetch });
    assert.equal(lines(got)[0], "codex: ready (check: docs index)");
    assert.ok(lines(got).includes(`docs index: unreachable (HTTP 404, ${DOCS})`), got.stdout);
  });

  test("a help command the CLI rejects is named and leaves no file", async () => {
    const w = world({ help: { "--help": realHelp["--help"], "exec --help": realHelp["exec --help"] } });
    const got = await update({ ...w.opts, fetch: web().fetch });
    const facts = join(w.dataDir, "cli-facts", "codex", "0.168.0");
    assert.equal(lines(got)[0], "codex: ready (check: cli facts)");
    assert.ok(lines(got).includes(`cli facts: ${facts} (exec-review: exec review --help exited 2)`), got.stdout);
    assert.ok(!existsSync(join(facts, "exec-review.txt")));
    assert.ok(existsSync(join(facts, "exec.txt")));
  });

  test("help a CLI prints on stderr with an empty stdout is cached", async () => {
    const w = world({ help_stderr: ["--help"] });
    const got = await update({ ...w.opts, fetch: web().fetch });
    const facts = join(w.dataDir, "cli-facts", "codex", "0.168.0");
    assert.equal(lines(got)[0], "codex: ready", got.stdout);
    assert.equal(readFileSync(join(facts, "codex.txt"), "utf8"), readFileSync(realHelp["--help"], "utf8"));
  });

  test("a help command that prints nothing is named, leaves no file, and keeps update from reading plain ready", async () => {
    const w = world({ help_empty: ["exec review --help"] });
    const got = await update({ ...w.opts, fetch: web().fetch });
    const facts = join(w.dataDir, "cli-facts", "codex", "0.168.0");
    assert.equal(lines(got)[0], "codex: ready (check: cli facts)");
    assert.ok(lines(got).includes(`cli facts: ${facts} (exec-review: exec review --help printed nothing)`), got.stdout);
    assert.ok(!existsSync(join(facts, "exec-review.txt")));
  });

  test("a logged-out CLI is unavailable, and the breaker it opened stays open", async () => {
    const w = world({ login_exit: 1 });
    openBreaker(w.dataDir, "codex", { failureClass: "not-logged-in", reason: "not logged in", now: noon, cooldownHours: 24 });
    const got = await update({ ...w.opts, fetch: web().fetch });
    assert.equal(lines(got)[0], "codex: unavailable: not logged in. Log in with codex, then run: external-agents update codex");
    assert.ok(lines(got).includes("login: not logged in"), got.stdout);
    assert.equal(got.code, 4);
    assert.equal(readBreaker(w.dataDir, "codex").class, "not-logged-in");
  });

  test("a present, logged-in CLI closes an open breaker", async () => {
    const w = world();
    openBreaker(w.dataDir, "codex", { failureClass: "not-logged-in", reason: "not logged in", now: noon, cooldownHours: 24 });
    await update({ ...w.opts, fetch: web().fetch });
    assert.equal(readBreaker(w.dataDir, "codex"), null);
  });

  test("a missing CLI points to the dotfiles install and installs nothing", async () => {
    const w = world();
    const empty = join(w.opts.cwd, "empty-path");
    mkdirSync(empty);
    const net = web();
    const got = await update({ ...w.opts, binary: undefined, env: { PATH: empty, PATHEXT: ".EXE" }, fetch: net.fetch });
    assert.match(got.stdout, /^codex: unavailable: codex not found \(tried .*\)\. This command never installs anything: install codex through your dotfiles install, or set codex\.binary_path, then run: external-agents update codex\n$/);
    assert.equal(got.code, 4);
    assert.ok(!existsSync(join(w.dataDir, "cli-facts")));
    assert.deepEqual(net.calls, []);
  });

  test("a CLI that prints no version is failed", async () => {
    const w = world({ version: "something odd\n" });
    const got = await update({ ...w.opts, fetch: web().fetch });
    assert.equal(got.stdout, "codex: failed (codex --version printed no version)\n");
    assert.equal(got.code, 1);
  });

  test("an unexpected error is one status line, not a stack trace", async () => {
    const w = world();
    const file = join(w.dataDir, "file");
    writeFileSync(file, "");
    const got = await update({ ...w.opts, dataDir: join(file, "x"), fetch: web().fetch });
    assert.match(got.stdout, /^codex: failed \([^\n]+\)\n$/);
    assert.equal(got.stderr, "");
    assert.equal(got.code, 1);
  });
});

describe("what update checks, from the provider record", () => {
  test("the config keys are every key the runner passes with the config flag", () => {
    assert.deepEqual(configKeys(codex), ["approval_policy", "sandbox_mode", "model_reasoning_effort"]);
  });

  test("a record with no login_status says login was not checked and stays ready", async () => {
    const root = join(scratch, "no-login-record");
    mkdirSync(join(root, "providers"), { recursive: true });
    const text = readFileSync(join(here, "..", "providers", "codex.yaml"), "utf8");
    writeFileSync(join(root, "providers", "codex.yaml"), text.replace(/^login_status:\n {2}args: \[login, status\]\n/m, ""));
    const w = world();
    const got = await update({ ...w.opts, providersRoot: root, fetch: web().fetch });
    assert.equal(lines(got)[0], "codex: ready");
    assert.ok(lines(got).includes("login: not checked (no login_status in the record)"), got.stdout);
    assert.equal(got.code, 0);
  });

  test("the release source follows the install channel the binary's path shows", () => {
    assert.equal(versionSource(codex, join(scratch, "AppData", "Roaming", "npm", "codex.cmd")), "npm:@openai/codex");
    assert.equal(versionSource(codex, join(scratch, "lib", "node_modules", "@openai", "codex", "bin", "codex.js")), "npm:@openai/codex");
    assert.equal(versionSource(codex, join(scratch, "AppData", "Local", "Programs", "OpenAI", "Codex", "bin", "codex.exe")), "github:openai/codex");
  });

  test("help names must be safe file names and markers must name a source", () => {
    const record = structuredClone(codex);
    record.help["../x"] = ["--help"];
    record.version.markers.pip = ["site-packages"];
    record.config_reference = "http://example.com";
    const problems = validateProvider(record).join("\n");
    assert.match(problems, /help\.\.\.\/x/);
    assert.match(problems, /version\.markers\.pip/);
    assert.match(problems, /config_reference/);
    assert.deepEqual(validateProvider(loadProvider("antigravity", fixtures)), []);
  });
});

describe("the update command", () => {
  test("update with no product is a usage error", () => {
    const { CLAUDE_PLUGIN_DATA: _unset, ...bare } = process.env;
    const got = spawnSync(process.execPath, [join(here, "..", "bin", "external-agents"), "update"], { encoding: "utf8", cwd: scratch, env: { ...bare, CLAUDE_PLUGIN_DATA: join(scratch, "external-agents-cli-data") } });
    assert.equal(got.status, 2);
    assert.match(got.stdout, /^external-agents: refused: invalid product/);
  });
});
