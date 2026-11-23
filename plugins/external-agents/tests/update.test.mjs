import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { openBreaker, readBreaker } from "../scripts/lib/breaker.mjs";
import { loadProvider, validateProvider } from "../scripts/lib/provider.mjs";
import { effortChoices, models } from "../scripts/lib/models.mjs";
import { update, configKeys, readCachedPage, versionSource } from "../scripts/lib/update.mjs";
import { usage } from "../scripts/lib/usage.mjs";

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
const catalog = readFileSync(join(fixtures, "codex-models.json"), "utf8");
const referenceText = 'key: "approval_policy",\nkey: "sandbox_mode",\nkey: "model_reasoning_effort",\n';

function web({ latest = "rust-v0.168.0", docs = 200, reference = referenceText } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, method: init.method ?? "GET" });
    if (url === RELEASES) return { ok: true, status: 200, json: async () => ({ tag_name: latest }) };
    if (url === DOCS) return { ok: docs === 200, status: docs };
    throw new Error(`unexpected fetch ${url}`);
  };
  const readPage = (url) => {
    calls.push({ url, method: "cached read" });
    if (url !== REFERENCE) throw new Error(`unexpected page ${url}`);
    if (reference instanceof Error) throw reference;
    return reference;
  };
  return { fetch, readPage, calls, opts: { fetch, readPage } };
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
  writeFileSync(file, JSON.stringify({ record: join(root, "calls.jsonl"), version: "codex-cli 0.168.0\n", help: realHelp, answers: { "debug models": { stdout: catalog } }, ...scenario }));
  return { opts: { product: "codex", cwd, dataDir, binary: fakeCodex, now: () => noon, env: { ...process.env, FAKE_SCENARIO: file } }, dataDir };
}
const lines = (got) => got.stdout.split("\n");

describe("update", () => {
  test("a present, logged-in CLI reports its version and login, caches its help per version, and checks release, docs and config keys", async () => {
    const w = world();
    const net = web();
    const got = await update({ ...w.opts, ...net.opts });
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
    assert.equal(readFileSync(join(facts, "models.txt"), "utf8"), catalog, "the model list is cached beside the help");
    assert.ok(net.calls.some((c) => c.url === DOCS && c.method === "HEAD"), "the docs index is HEAD-checked");
  });

  test("a second update the same day says the daily checks already ran", async () => {
    const w = world();
    await update({ ...w.opts, ...web().opts });
    const again = await update({ ...w.opts, ...web().opts });
    assert.ok(lines(again).includes("version check: already checked today"), again.stdout);
    assert.ok(lines(again).includes("routing: checked earlier today"), again.stdout);
    assert.equal(again.code, 0);
  });

  test("a CLI behind its latest release gets the configured update hint", async () => {
    const w = world({}, { local: "schema: 1\ncodex:\n  update_hint: Run the dotfiles update.\n" });
    const got = await update({ ...w.opts, ...web({ latest: "rust-v0.171.0" }).opts });
    assert.ok(lines(got).includes("version check: codex 0.168.0 is behind 0.171.0. Run the dotfiles update."), got.stdout);
  });

  test("a config key missing from both the help and the config reference is reported as drift", async () => {
    const w = world();
    const got = await update({ ...w.opts, ...web({ reference:'key: "approval_policy",\nkey: "model_reasoning_effort",\nallowed_sandbox_modes\n' }).opts });
    assert.equal(lines(got)[0], "codex: ready (check: config keys)");
    assert.ok(lines(got).includes(`config keys: drift: sandbox_mode is in neither the CLI help nor ${REFERENCE}`), got.stdout);
    assert.equal(got.code, 0);
  });

  test("a config reference that cannot be read leaves the keys unverified, not drifted", async () => {
    const w = world();
    const got = await update({ ...w.opts, ...web({ reference: new Error("getaddrinfo ENOTFOUND") }).opts });
    assert.ok(lines(got).includes(`config keys: unverified: approval_policy, sandbox_mode, model_reasoning_effort are not in the CLI help, and ${REFERENCE} could not be read (getaddrinfo ENOTFOUND)`), got.stdout);
  });

  test("a model list command that fails is named under cli facts", async () => {
    const w = world({ answers: { "debug models": { exit: 2 } } });
    const got = await update({ ...w.opts, ...web().opts });
    assert.equal(lines(got)[0], "codex: ready (check: cli facts)");
    assert.ok(lines(got).includes(`cli facts: ${join(w.dataDir, "cli-facts", "codex", "0.168.0")} (models: debug models exited 2)`), got.stdout);
  });

  test("an unreachable docs index is reported", async () => {
    const w = world();
    const got = await update({ ...w.opts, ...web({ docs: 404 }).opts });
    assert.equal(lines(got)[0], "codex: ready (check: docs index)");
    assert.ok(lines(got).includes(`docs index: unreachable (HTTP 404, ${DOCS})`), got.stdout);
  });

  test("a help command the CLI rejects is named and leaves no file", async () => {
    const w = world({ help: { "--help": realHelp["--help"], "exec --help": realHelp["exec --help"] } });
    const got = await update({ ...w.opts, ...web().opts });
    const facts = join(w.dataDir, "cli-facts", "codex", "0.168.0");
    assert.equal(lines(got)[0], "codex: ready (check: cli facts)");
    assert.ok(lines(got).includes(`cli facts: ${facts} (exec-review: exec review --help exited 2)`), got.stdout);
    assert.ok(!existsSync(join(facts, "exec-review.txt")));
    assert.ok(existsSync(join(facts, "exec.txt")));
  });

  test("help a CLI prints on stderr with an empty stdout is cached", async () => {
    const w = world({ help_stderr: ["--help"] });
    const got = await update({ ...w.opts, ...web().opts });
    const facts = join(w.dataDir, "cli-facts", "codex", "0.168.0");
    assert.equal(lines(got)[0], "codex: ready", got.stdout);
    assert.equal(readFileSync(join(facts, "codex.txt"), "utf8"), readFileSync(realHelp["--help"], "utf8"));
  });

  test("a help command that prints nothing is named, leaves no file, and keeps update from reading plain ready", async () => {
    const w = world({ help_empty: ["exec review --help"] });
    const got = await update({ ...w.opts, ...web().opts });
    const facts = join(w.dataDir, "cli-facts", "codex", "0.168.0");
    assert.equal(lines(got)[0], "codex: ready (check: cli facts)");
    assert.ok(lines(got).includes(`cli facts: ${facts} (exec-review: exec review --help printed nothing)`), got.stdout);
    assert.ok(!existsSync(join(facts, "exec-review.txt")));
  });

  test("a logged-out CLI is unavailable, and the breaker it opened stays open", async () => {
    const w = world({ login_exit: 1 });
    openBreaker(w.dataDir, "codex", { failureClass: "not-logged-in", reason: "not logged in", now: noon, cooldownHours: 24 });
    const got = await update({ ...w.opts, ...web().opts });
    assert.equal(lines(got)[0], "codex: unavailable: not logged in. Log in with codex, then run: external-agents update codex");
    assert.ok(lines(got).includes("login: not logged in"), got.stdout);
    assert.equal(got.code, 4);
    assert.equal(readBreaker(w.dataDir, "codex").class, "not-logged-in");
  });

  test("a present, logged-in CLI closes an open breaker", async () => {
    const w = world();
    openBreaker(w.dataDir, "codex", { failureClass: "not-logged-in", reason: "not logged in", now: noon, cooldownHours: 24 });
    await update({ ...w.opts, ...web().opts });
    assert.equal(readBreaker(w.dataDir, "codex"), null);
  });

  test("a missing CLI points to the dotfiles install and installs nothing", async () => {
    const w = world();
    const empty = join(w.opts.cwd, "empty-path");
    mkdirSync(empty);
    const net = web();
    const got = await update({ ...w.opts, binary: undefined, env: { PATH: empty, PATHEXT: ".EXE" }, ...net.opts });
    assert.match(got.stdout, /^codex: unavailable: codex not found \(tried .*\)\. This command never installs anything: install codex through your dotfiles install, or set codex\.binary_path, then run: external-agents update codex\n$/);
    assert.equal(got.code, 4);
    assert.ok(!existsSync(join(w.dataDir, "cli-facts")));
    assert.deepEqual(net.calls, []);
  });

  test("a CLI that prints no version is failed", async () => {
    const w = world({ version: "something odd\n" });
    const got = await update({ ...w.opts, ...web().opts });
    assert.equal(got.stdout, "codex: failed (codex --version printed no version)\n");
    assert.equal(got.code, 1);
  });

  test("an unexpected error is one status line, not a stack trace", async () => {
    const w = world();
    const file = join(w.dataDir, "file");
    writeFileSync(file, "");
    const got = await update({ ...w.opts, dataDir: join(file, "x"), ...web().opts });
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
    const got = await update({ ...w.opts, providersRoot: root, ...web().opts });
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

describe("the config reference read", () => {
  function pageEnv(name, pages = {}) {
    const root = join(scratch, name);
    const pagesDir = join(root, "pages");
    for (const [slug, text] of Object.entries(pages)) {
      mkdirSync(dirname(join(pagesDir, slug)), { recursive: true });
      writeFileSync(join(pagesDir, slug), text);
    }
    return { ...process.env, FETCH_DOCS_FIXTURE_DIR: pagesDir, DOCS_CACHE_DIR: join(root, "cache"), FETCH_DOCS_CLAUDE_BIN: "" };
  }

  test("goes through the plugin's fetch-docs.sh copy and the docs cache, and returns the page's text", () => {
    const env = pageEnv("page-read", { "learn-chatgpt-com/docs/config-file/config-reference.md": referenceText });
    assert.equal(readCachedPage(REFERENCE, env), referenceText);
    assert.ok(existsSync(join(scratch, "page-read", "cache")), "the read is stored in the docs cache");
  });

  test("a page fetch-docs.sh leaves unread throws with its reason", () => {
    assert.throws(() => readCachedPage(REFERENCE, pageEnv("page-missing")), /fixture-missing/);
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

const fakeAgy = { path: process.execPath, args: [join(fixtures, "fake-agy.mjs")], shell: false };
const agyHelp = "Usage: agy [options]\n  --effort                        Reasoning effort (low|medium|high)\n  --model                         Model\n";
const agyModels = "model-x-high\tModel X (High)\nmodel-x-low\tModel X (Low)\n";

function agyWorld(answers = {}) {
  const root = join(scratch, `w${(count += 1)}`);
  const cwd = join(root, "cwd");
  mkdirSync(cwd, { recursive: true });
  const file = join(root, "scenario.json");
  writeFileSync(file, JSON.stringify({ record: join(root, "calls.jsonl"), answers: { "--help": { stdout: agyHelp }, models: { stdout: agyModels }, ...answers } }));
  const calls = () => readFileSync(join(root, "calls.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l).argv.join(" "));
  return { opts: { product: "antigravity", cwd, dataDir: join(root, "data"), binary: fakeAgy, now: () => noon, env: { ...process.env, FAKE_SCENARIO: file } }, calls };
}

describe("models", () => {
  test("agy's models and the effort choices its help lists are one JSON document, with harness facts, breaker and each source named", async () => {
    const got = await models(agyWorld().opts);
    assert.equal(got.code, 0);
    assert.deepEqual(JSON.parse(got.stdout), {
      schema: 1,
      product: "antigravity",
      status: "ok",
      cli: { name: "agy", version: "1.0.0" },
      unset_model: "cli-default",
      models: [{ id: "model-x-high", name: "Model X (High)" }, { id: "model-x-low", name: "Model X (Low)" }],
      models_source: "agy models",
      efforts: ["low", "medium", "high"],
      efforts_source: "agy --help (--effort)",
      tools: ["file", "shell", "web", "mcp", "invoke_subagent", "define_subagent", "manage_subagents", "send_message", "run_workflow", "generate_image"],
      image: true,
      breaker: { open: false, reason: null, reset_at: null },
      docs_index: "https://antigravity.google/docs/cli",
    });
  });

  test("a second call reads the cache for the installed version and asks the CLI only for its version", async () => {
    const w = agyWorld();
    await models(w.opts);
    const before = w.calls().length;
    await models(w.opts);
    assert.deepEqual(w.calls().slice(before), ["--version"]);
  });

  test("help whose effort line lists no readable choices is failed, exit 1, naming the command", async () => {
    const got = await models(agyWorld({ "--help": { stdout: "  --effort=<level>  Reasoning effort: low, medium, high\n" } }).opts);
    assert.equal(got.code, 1);
    assert.deepEqual(JSON.parse(got.stdout), { schema: 1, product: "antigravity", status: "failed", reason: "agy --help lists no --effort choices this record can read" });
  });

  test("an empty cached file is asked for again", async () => {
    const w = agyWorld();
    const dir = join(w.opts.dataDir, "cli-facts", "antigravity", "1.0.0");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "agy.txt"), "");
    const doc = JSON.parse((await models(w.opts)).stdout);
    assert.deepEqual(doc.efforts, ["low", "medium", "high"]);
    assert.ok(w.calls().includes("--help"));
  });

  test("Codex's catalog gives each listed model its own effort levels, default and optional context_window, leaves hidden models out, and reports harness facts and breaker", async () => {
    const withWindow = JSON.stringify({
      models: [
        { slug: "model-a", display_name: "Model A", visibility: "list", default_reasoning_level: "low", supported_reasoning_levels: [{ effort: "low" }, { effort: "high" }], context_window: 256000 },
        { slug: "model-b", display_name: "Model B", visibility: "list", default_reasoning_level: "medium", supported_reasoning_levels: [{ effort: "medium" }] },
        { slug: "model-hidden", display_name: "Hidden", visibility: "hide", default_reasoning_level: "medium", supported_reasoning_levels: [{ effort: "medium" }], context_window: 128000 },
      ],
    });
    const got = await models(world({ answers: { "debug models": { stdout: withWindow } } }).opts);
    const doc = JSON.parse(got.stdout);
    assert.equal(got.code, 0);
    assert.equal(doc.schema, 1);
    assert.deepEqual(doc.models, [
      { id: "model-a", name: "Model A", efforts: ["low", "high"], default_effort: "low", context_window: 256000 },
      { id: "model-b", name: "Model B", efforts: ["medium"], default_effort: "medium" },
    ]);
    assert.equal(Object.hasOwn(doc.models[1], "context_window"), false);
    assert.equal(doc.models_source, "codex debug models");
    assert.equal(doc.cli.version, "0.168.0");
    assert.ok(!("efforts" in doc));
    assert.deepEqual(doc.tools, ["file", "shell", "web", "mcp", "image_generation"]);
    assert.equal(doc.image, true);
    assert.deepEqual(doc.breaker, { open: false, reason: null, reset_at: null });
  });

  test("an open breaker is reported in models output, and an expired breaker reports closed", async () => {
    const w = world();
    const resetAt = "2026-11-22T15:00:00.000Z";
    openBreaker(w.dataDir, "codex", { failureClass: "usage-limit", reason: "usage limit hit", now: noon, resetAt, cooldownHours: 24 });
    const openDoc = JSON.parse((await models(w.opts)).stdout);
    assert.equal(openDoc.status, "ok");
    assert.deepEqual(openDoc.breaker, { open: true, reason: "usage limit hit", reset_at: resetAt });

    const laterDoc = JSON.parse((await models({ ...w.opts, now: () => Date.parse(resetAt) + 1000 })).stdout);
    assert.deepEqual(laterDoc.breaker, { open: false, reason: null, reset_at: null });
  });

  test("a missing CLI is unavailable, exit 4, still JSON, and nothing is cached", async () => {
    const w = world();
    const empty = join(w.opts.cwd, "empty-path");
    mkdirSync(empty);
    const got = await models({ ...w.opts, binary: undefined, env: { PATH: empty, PATHEXT: ".EXE" } });
    const doc = JSON.parse(got.stdout);
    assert.equal(got.code, 4);
    assert.equal(doc.status, "unavailable");
    assert.match(doc.reason, /^codex not found/);
    assert.ok(!existsSync(join(w.dataDir, "cli-facts")));
  });

  test("a model list the record cannot read is failed, exit 1, naming the command", async () => {
    const got = await models(world({ answers: { "debug models": { stdout: "not json" } } }).opts);
    assert.equal(got.code, 1);
    assert.match(JSON.parse(got.stdout).reason, /^codex debug models printed output this record cannot read/);
  });

  test("effort choices come only from the effort flag's own line", () => {
    assert.deepEqual(effortChoices(agyHelp, "--effort"), ["low", "medium", "high"]);
    assert.equal(effortChoices("  --effort-mode   pick (a|b)\n", "--effort"), null);
    assert.equal(effortChoices("  --effort   no list here\n", "--effort"), null);
  });

  test("an unknown product is refused with exit 2, as JSON", () => {
    const { CLAUDE_PLUGIN_DATA: _unset, ...bare } = process.env;
    const got = spawnSync(process.execPath, [join(here, "..", "bin", "external-agents"), "models", "nope"], { encoding: "utf8", cwd: scratch, env: { ...bare, CLAUDE_PLUGIN_DATA: join(scratch, "external-agents-cli-data") } });
    assert.equal(got.status, 2);
    assert.deepEqual([JSON.parse(got.stdout).product, JSON.parse(got.stdout).status], ["nope", "refused"]);
  });
});

describe("usage", () => {
  const bin = join(here, "..", "bin", "external-agents");
  const windows = process.platform === "win32";

  function cliEnv(root, { product, fake, scenario }) {
    const cwd = join(root, "cwd");
    const home = join(cwd, "docs", "conventions");
    const tools = join(root, "tools");
    const dataDir = join(root, "external-agents-cli-data");
    mkdirSync(home, { recursive: true });
    mkdirSync(tools, { recursive: true });
    mkdirSync(dataDir, { recursive: true });
    const binaryName = product === "antigravity" ? "agy" : product;
    const wrapper = join(tools, windows ? `${binaryName}.cmd` : binaryName);
    writeFileSync(wrapper, windows ? `@"${process.execPath}" "${fake}" %*\r\n` : `#!/bin/sh\nexec "${process.execPath}" "${fake}" "$@"\n`);
    chmodSync(wrapper, 0o755);
    writeFileSync(join(home, "external-agents.local.yaml"), `schema: 1\n${product}:\n  binary_path: "${wrapper.replace(/\\/g, "/")}"\n`);
    const scenarioFile = join(root, "scenario.json");
    const callsFile = join(root, "calls.jsonl");
    writeFileSync(scenarioFile, JSON.stringify({ record: callsFile, ...scenario }));
    const { CLAUDE_PLUGIN_DATA: _unset, ...bare } = process.env;
    return {
      cwd,
      dataDir,
      env: { ...bare, CLAUDE_PLUGIN_DATA: dataDir, FAKE_SCENARIO: scenarioFile },
      calls: () => (existsSync(callsFile) ? readFileSync(callsFile, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l)) : []),
    };
  }

  test("Codex usage sends initialize, initialized and account/rateLimits/read, ignores notifications, normalizes percent used, and prints no account or plan fields", async () => {
    const root = join(scratch, `u${(count += 1)}`);
    const resetEpoch = 1795420800;
    const env = cliEnv(root, {
      product: "codex",
      fake: join(fixtures, "fake-codex.mjs"),
      scenario: {
        app_server: {
          messages: [
            { id: 0, result: { userAgent: "fake-codex/0.1.0" } },
            { method: "remoteControl/status/changed", params: { enabled: false } },
            {
              id: 1,
              result: {
                rateLimits: {
                  limitId: "acct_secret_99",
                  planType: "super-secret-plan",
                  primary: { usedPercent: 28, windowDurationMins: 300, resetsAt: resetEpoch },
                  secondary: null,
                },
                ordinaryUsageAllowed: true,
              },
            },
          ],
        },
      },
    });
    const got = spawnSync(process.execPath, [bin, "usage", "codex"], { encoding: "utf8", cwd: env.cwd, env: env.env });
    assert.equal(got.status, 0, got.stdout + got.stderr);
    assert.doesNotMatch(got.stdout, /acct_secret_99|super-secret-plan/);
    assert.deepEqual(JSON.parse(got.stdout), {
      status: "ok",
      remaining: 0.72,
      window: "5h",
      resets_at: new Date(resetEpoch * 1000).toISOString(),
      source: "codex app-server (account/rateLimits/read)",
    });
    const calls = env.calls();
    assert.equal(calls.length, 1);
    assert.deepEqual(calls[0].argv, ["app-server"]);
    const sent = calls[0].stdin_lines.map((l) => JSON.parse(l));
    assert.equal(sent[0].method, "initialize");
    assert.equal(sent[1].method, "initialized");
    assert.deepEqual(sent[2], { method: "account/rateLimits/read", id: 1 });
  });

  test("usage codex reports the secondary window when it has less left than the primary", () => {
    const root = join(scratch, `u${(count += 1)}`);
    const env = cliEnv(root, {
      product: "codex",
      fake: join(fixtures, "fake-codex.mjs"),
      scenario: {
        app_server: {
          messages: [
            { id: 0, result: { userAgent: "fake-codex/0.1.0" } },
            {
              id: 1,
              result: {
                rateLimits: {
                  primary: { usedPercent: 10, windowDurationMins: 300, resetsAt: 1795420800 },
                  secondary: { usedPercent: 100, windowDurationMins: 10080, resetsAt: 1795900000 },
                },
              },
            },
          ],
        },
      },
    });
    const got = spawnSync(process.execPath, [bin, "usage", "codex"], { encoding: "utf8", cwd: env.cwd, env: env.env });
    assert.equal(got.status, 0, got.stdout + got.stderr);
    const reading = JSON.parse(got.stdout);
    assert.equal(reading.remaining, 0);
    assert.equal(reading.window, "7d");
    assert.equal(reading.resets_at, new Date(1795900000 * 1000).toISOString());
    assert.deepEqual(reading.windows.map((w) => w.group), ["primary", "secondary"]);
    assert.equal(reading.group, undefined);
  });

  test("Antigravity usage runs without --disable-slash-commands, parses tab lines, reports lowest remaining with all windows, and prints no email or plan", async () => {
    const response = [
      "Account: person@example.com (Secret Tier)",
      "Group A\tFive Hour Limit Remaining\t80%\t2026-11-23T05:00:00Z",
      "Group A\tWeekly Limit Remaining\t45%\t2026-11-28T00:00:00Z",
      "Group B\tFive Hour Limit Remaining\t100%\t2026-11-23T05:00:00Z",
      "Group B\tWeekly Limit Remaining\t90%\t2026-11-28T00:00:00Z",
    ].join("\n");
    const w = agyWorld({ "--output-format json -p=/usage": { stdout: `${JSON.stringify({ status: "SUCCESS", num_turns: 0, response })}\n` } });
    const got = await usage(w.opts);
    assert.equal(got.code, 0, got.stdout + got.stderr);
    assert.doesNotMatch(got.stdout, /person@example\.com|Secret Tier/);
    assert.deepEqual(JSON.parse(got.stdout), {
      status: "ok",
      remaining: 0.45,
      window: "Weekly",
      resets_at: "2026-11-28T00:00:00Z",
      windows: [
        { group: "Group A", window: "Five Hour", remaining: 0.8, resets_at: "2026-11-23T05:00:00Z" },
        { group: "Group A", window: "Weekly", remaining: 0.45, resets_at: "2026-11-28T00:00:00Z" },
        { group: "Group B", window: "Five Hour", remaining: 1, resets_at: "2026-11-23T05:00:00Z" },
        { group: "Group B", window: "Weekly", remaining: 0.9, resets_at: "2026-11-28T00:00:00Z" },
      ],
      source: "agy --output-format json -p=/usage",
    });
    assert.deepEqual(w.calls(), ["--output-format json -p=/usage"]);
  });

  test("Antigravity usage works through the external-agents CLI and passes -p=/usage intact", () => {
    const root = join(scratch, `u${(count += 1)}`);
    const response = "Group A\tFive Hour Limit Remaining\t65%\t2026-11-23T05:00:00Z\n";
    const env = cliEnv(root, {
      product: "antigravity",
      fake: join(fixtures, "fake-agy.mjs"),
      scenario: {
        answers: {
          "--output-format json -p=/usage": { stdout: `${JSON.stringify({ status: "SUCCESS", num_turns: 0, response })}\n` },
        },
      },
    });
    const got = spawnSync(process.execPath, [bin, "usage", "antigravity"], { encoding: "utf8", cwd: env.cwd, env: env.env });
    assert.equal(got.status, 0, got.stdout + got.stderr);
    const doc = JSON.parse(got.stdout);
    assert.equal(doc.status, "ok");
    assert.equal(doc.remaining, 0.65);
    assert.equal(doc.window, "Five Hour");
    assert.equal(doc.windows.length, 1);
    assert.deepEqual(env.calls()[0].argv, ["--output-format", "json", "-p=/usage"]);
  });

  test("Codex usage returns unavailable on timeout", async () => {
    const w = world({ app_server: { hang_ms: 5000 } });
    const got = await usage({ ...w.opts, timeoutMs: 250 });
    assert.equal(got.code, 4);
    const doc = JSON.parse(got.stdout);
    assert.equal(doc.status, "unavailable");
    assert.equal(doc.source, "codex app-server (account/rateLimits/read)");
    assert.match(doc.reason, /timed out/);
  });

  test("Codex usage returns unavailable on early exit or unparsable reply", async () => {
    const exited = await usage(world({ app_server: { exit: 1 } }).opts);
    assert.equal(exited.code, 4);
    assert.equal(JSON.parse(exited.stdout).status, "unavailable");

    const badShape = await usage(world({ app_server: { messages: [{ id: 1, result: { rateLimits: {} } }] } }).opts);
    assert.equal(badShape.code, 4);
    assert.equal(JSON.parse(badShape.stdout).status, "unavailable");

    const rpcErr = await usage(world({ app_server: { messages: [{ id: 1, error: { code: -32000, message: "not logged in" } }] } }).opts);
    assert.equal(rpcErr.code, 4);
    assert.equal(JSON.parse(rpcErr.stdout).status, "unavailable");
  });

  test("Antigravity usage returns unavailable on exit 2, unparsable output, or timeout", async () => {
    const exit2 = await usage(agyWorld({ "--output-format json -p=/usage": { exit: 2 } }).opts);
    assert.equal(exit2.code, 4);
    assert.deepEqual(JSON.parse(exit2.stdout), { status: "unavailable", source: "agy --output-format json -p=/usage", reason: "exited 2" });

    const notJson = await usage(agyWorld({ "--output-format json -p=/usage": { stdout: "not json at all\n" } }).opts);
    assert.equal(notJson.code, 4);
    assert.equal(JSON.parse(notJson.stdout).status, "unavailable");

    const noLines = await usage(agyWorld({ "--output-format json -p=/usage": { stdout: `${JSON.stringify({ status: "SUCCESS", response: "nothing parsable here" })}\n` } }).opts);
    assert.equal(noLines.code, 4);
    assert.equal(JSON.parse(noLines.stdout).status, "unavailable");

    const timedOut = await usage({ ...agyWorld({ "--output-format json -p=/usage": { sleep_ms: 5000 } }).opts, timeoutMs: 250 });
    assert.equal(timedOut.code, 4);
    const doc = JSON.parse(timedOut.stdout);
    assert.equal(doc.status, "unavailable");
    assert.match(doc.reason, /timed out/);
  });

  test("usage prints unavailable with exit 2 for an unknown product, and --help lists usage", () => {
    const { CLAUDE_PLUGIN_DATA: _unset, ...bare } = process.env;
    const env = { ...bare, CLAUDE_PLUGIN_DATA: join(scratch, "external-agents-cli-data") };
    const bad = spawnSync(process.execPath, [bin, "usage", "nope"], { encoding: "utf8", cwd: scratch, env });
    assert.equal(bad.status, 2);
    assert.equal(JSON.parse(bad.stdout).status, "unavailable");
    const help = spawnSync(process.execPath, [bin, "--help"], { encoding: "utf8", cwd: scratch, env });
    assert.equal(help.status, 0);
    assert.match(help.stdout, /^\s+usage <product>/m);
  });
});
