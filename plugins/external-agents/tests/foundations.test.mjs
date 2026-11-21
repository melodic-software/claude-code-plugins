import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { loadConfig, pluginRoot } from "../scripts/lib/config.mjs";
import { loadProvider, validateProvider } from "../scripts/lib/provider.mjs";
import { resolveBinary, unavailableMessage } from "../scripts/lib/binary.mjs";
import { listJobs, newJobId, pruneJobs, readJob, repoKey, writeJob } from "../scripts/lib/jobs.mjs";

const scratch = mkdtempSync(join(tmpdir(), "external-agents-foundations-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
const dir = (...parts) => {
  const path = join(scratch, ...parts);
  mkdirSync(path, { recursive: true });
  return path;
};

describe("config", () => {
  test("bundled defaults match the defaults the schema documents", () => {
    const { values, provenance } = loadConfig({ projectRoot: dir("empty-repo") });
    const documented = [];
    const walk = (node, path) => {
      if (node.default !== undefined) documented.push([path, node.default]);
      for (const [key, child] of Object.entries(node.properties ?? {})) walk(child, [...path, key]);
    };
    walk(JSON.parse(readFileSync(join(pluginRoot, "schemas", "external-agents.schema.json"), "utf8")), []);
    assert.ok(documented.length >= 7, "the schema documents the bundled defaults");
    for (const [path, value] of documented) {
      assert.deepEqual(path.reduce((v, k) => v?.[k], values), value, path.join("."));
      assert.equal(provenance[path.join(".")], "defaults", path.join("."));
    }
    assert.equal(values.codex.model, undefined);
  });

  test("binary_path is taken only from the personal layer, and only when absolute", () => {
    const root = dir("binary-path");
    const home = dir("binary-path", "docs", "conventions");
    writeFileSync(join(home, "external-agents.yaml"), "schema: 1\ncodex:\n  binary_path: /tmp/team-chosen\n");
    const team = loadConfig({ projectRoot: root });
    assert.equal(team.values.codex.binary_path, undefined, "a committed team file never picks the executable");
    assert.ok(team.errors.some((e) => e.includes("codex.binary_path")), team.errors.join("\n"));
    writeFileSync(join(home, "external-agents.local.yaml"), "schema: 1\ncodex:\n  binary_path: relative/codex\n");
    const relative = loadConfig({ projectRoot: root });
    assert.equal(relative.values.codex.binary_path, undefined);
    assert.ok(relative.errors.some((e) => e.includes("absolute")), relative.errors.join("\n"));
    const absolute = join(root, "bin", "codex");
    writeFileSync(join(home, "external-agents.local.yaml"), `schema: 1\ncodex:\n  binary_path: "${absolute.replace(/\\/g, "/")}"\n`);
    assert.equal(loadConfig({ projectRoot: root }).values.codex.binary_path, absolute.replace(/\\/g, "/"));
  });

  test("team layer refines a key and personal layer refines the team", () => {
    const root = dir("layered");
    const home = dir("layered", "docs", "conventions");
    writeFileSync(join(home, "external-agents.yaml"), "schema: 1\ncodex:\n  model: team-model\n  uses:\n    task:\n      mode: read-only\n");
    writeFileSync(join(home, "external-agents.local.yaml"), "schema: 1\ncodex:\n  model: my-model\n");
    const { values, provenance } = loadConfig({ projectRoot: root });
    assert.equal(values.codex.uses.task.mode, "read-only");
    assert.equal(provenance["codex.uses.task.mode"], "team");
    assert.equal(values.codex.model, "my-model");
    assert.equal(provenance["codex.model"], "local");
  });

  test("an invalid team value is reported and the default stands", () => {
    const root = dir("invalid");
    writeFileSync(join(dir("invalid", "docs", "conventions"), "external-agents.yaml"), "schema: 1\ncodex:\n  uses:\n    review:\n      mode: write\n");
    const { values, errors } = loadConfig({ projectRoot: root });
    assert.equal(values.codex.uses.review.mode, "read-only");
    assert.ok(errors.some((e) => e.includes("codex.uses.review.mode")), errors.join("\n"));
  });
});

describe("provider record", () => {
  test("the bundled codex record loads and validates", () => {
    const codex = loadProvider("codex");
    assert.equal(codex.product, "codex");
    assert.equal(codex.binary.name, "codex");
    assert.equal(codex.unset_model, "cli-default");
    assert.match(codex.docs_index, /^https:\/\//);
    assert.equal(codex.modes["read-only"].enforcement, "sandbox");
    assert.equal(codex.modes.write.enforcement, "sandbox");
    assert.ok(codex.soft_deny.length > 0);
  });

  test("an unknown product is refused", () => {
    assert.throws(() => loadProvider("no-such-cli"), /no provider record/);
    assert.throws(() => loadProvider("../codex"), /invalid product/);
  });

  const valid = () => ({
    schema: 1,
    product: "demo",
    docs_index: "https://example.com/llms.txt",
    binary: { name: "demo" },
    version: { args: ["--version"] },
    unset_model: "skip-with-notice",
    modes: {
      "read-only": {
        enforcement: "approval-denial",
        settings: { agentMode: "" },
        settings_arg: "--settings",
        fallback_warning: { pattern: "continuing in the default mode", severity: "notice" },
      },
      write: { enforcement: "sandbox", args: { run: ["--mode", "auto"] } },
    },
    soft_deny: [
      { kind: "json_array_nonempty", field: "denied_actions" },
      { kind: "stderr_substring", text: "denied" },
    ],
  });

  test("a record using settings files, array soft-deny and notice warnings validates", () => {
    assert.deepEqual(validateProvider(valid()), []);
  });

  test("each malformed field is named", () => {
    const record = valid();
    record.modes.write.enforcement = "hope";
    record.soft_deny.push({ kind: "vibes" });
    record.modes["read-only"].fallback_warning.severity = "loud";
    delete record.binary;
    const problems = validateProvider(record).join("\n");
    assert.match(problems, /modes\.write\.enforcement/);
    assert.match(problems, /soft_deny\[2\]\.kind/);
    assert.match(problems, /fallback_warning\.severity/);
    assert.match(problems, /binary\.name/);
  });

  test("a mode map missing read-only or write is refused", () => {
    const record = valid();
    delete record.modes.write;
    assert.match(validateProvider(record).join("\n"), /modes\.write/);
  });
});

describe("binary resolution", () => {
  const record = { product: "demo", binary: { name: "demo", candidates: { win32: ["{LOCALAPPDATA}/Demo/demo.exe", "{APPDATA}/npm/demo.cmd"] } } };

  test("binary_path wins over every candidate", () => {
    const fake = join(dir("bin-override"), "custom-demo");
    writeFileSync(fake, "");
    const local = dir("bin-override-local");
    const onPath = dir("bin-override-path");
    mkdirSync(join(local, "Demo"), { recursive: true });
    writeFileSync(join(local, "Demo", "demo.exe"), "");
    writeFileSync(join(onPath, "demo.exe"), "");
    const found = resolveBinary(record, { binaryPath: fake, platform: "win32", env: { LOCALAPPDATA: local, PATH: onPath, PATHEXT: ".EXE" } });
    assert.equal(found.path, fake);
    assert.equal(found.source, "binary_path");
  });

  test("a binary_path that does not exist is reported, never skipped", () => {
    const found = resolveBinary(record, { binaryPath: join(scratch, "missing"), platform: "linux", env: { PATH: "" } });
    assert.equal(found.path, null);
    assert.match(found.tried.join(" "), /missing/);
  });

  test("on Windows the listed candidates are tried before PATH, in order", () => {
    const local = dir("win-local");
    const appdata = dir("win-appdata");
    const onPath = dir("win-path");
    mkdirSync(join(appdata, "npm"), { recursive: true });
    writeFileSync(join(appdata, "npm", "demo.cmd"), "");
    writeFileSync(join(onPath, "demo.exe"), "");
    const env = { LOCALAPPDATA: local, APPDATA: appdata, PATH: onPath, PATHEXT: ".EXE;.CMD" };
    const found = resolveBinary(record, { platform: "win32", env });
    assert.equal(found.path, join(appdata, "npm", "demo.cmd"));
    assert.equal(found.shell, true);
    mkdirSync(join(local, "Demo"), { recursive: true });
    writeFileSync(join(local, "Demo", "demo.exe"), "");
    const first = resolveBinary(record, { platform: "win32", env });
    assert.equal(first.path, join(local, "Demo", "demo.exe"));
    assert.equal(first.shell, false);
  });

  test("PATH is searched last, with PATHEXT on Windows", () => {
    const onPath = dir("path-only");
    writeFileSync(join(onPath, "demo.exe"), "");
    const found = resolveBinary(record, { platform: "win32", env: { PATH: onPath, PATHEXT: ".EXE;.CMD" } });
    assert.equal(found.path, join(onPath, "demo.exe"));
    assert.equal(found.source, "PATH");
  });

  test("a missing binary gives the unavailable message that points to update", () => {
    const found = resolveBinary(record, { platform: "linux", env: { PATH: dir("empty-path") } });
    assert.equal(found.path, null);
    const message = unavailableMessage(record, found);
    assert.match(message, /^demo: unavailable/);
    assert.match(message, /external-agents update demo/);
  });
});

describe("job store", () => {
  test("repo key hashes the git common dir, and is no-repo outside a repository", () => {
    const repo = dir("repo");
    execFileSync("git", ["-C", repo, "init", "-q"]);
    const key = repoKey(repo);
    assert.match(key, /^[0-9a-f]{16}$/);
    const worktree = join(scratch, "repo-wt");
    execFileSync("git", ["-C", repo, "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"]);
    execFileSync("git", ["-C", repo, "worktree", "add", "-q", "--detach", worktree]);
    assert.equal(repoKey(worktree), key, "a worktree shares its repository's key");
    assert.equal(repoKey(realpathSync(tmpdir())), "no-repo");
  });

  test("jobs are written, read, listed newest first and pruned to keep", () => {
    const data = dir("data");
    const ids = [];
    for (let i = 0; i < 4; i += 1) {
      const id = newJobId(Date.UTC(2026, 10, 21, 12, 0, i));
      ids.push(id);
      writeJob(data, "k1", { id, product: "codex", status: "ok", started_at: new Date(Date.UTC(2026, 10, 21, 12, 0, i)).toISOString() });
      writeFileSync(join(data, "jobs", "k1", `${id}.log`), "log");
    }
    writeJob(data, "k1", { id: "running-one", status: "running", started_at: "2026-01-01T00:00:00.000Z" });
    assert.equal(readJob(data, "k1", ids[2]).id, ids[2]);
    assert.equal(readJob(data, "k1", "absent"), null);
    assert.deepEqual(listJobs(data, "k1").map((j) => j.id).slice(0, 4), [...ids].reverse());
    pruneJobs(data, "k1", 2);
    const left = readdirSync(join(data, "jobs", "k1")).sort();
    assert.ok(left.includes(`${ids[3]}.json`) && left.includes(`${ids[2]}.json`));
    assert.ok(!left.some((f) => f.startsWith(ids[0]) || f.startsWith(ids[1])), left.join(","));
    assert.ok(left.includes("running-one.json"), "a running job is never pruned");
  });

  test("a job id cannot escape the jobs directory", () => {
    assert.throws(() => readJob(dir("data2"), "k1", "../x"), /invalid job id/);
    assert.throws(() => writeJob(dir("data2"), "../k", { id: "a" }), /invalid repo key/);
  });
});
