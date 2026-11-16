import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { tempDir, writeTree } from "../tests/temp.mjs";
import { InventoryError, installPlugin, inventory, knownMarketplaces, recordsFromCli, recordsFromDisk } from "./inventory.mjs";

function fixture() {
  const root = tempDir();
  writeTree(root, {
    "cache/impl/.claude-plugin/plugin.json": { name: "impl", dependencies: ["lib", "ext@vendor", { name: "obj" }] },
    "cache/impl/hooks/hooks.json": { hooks: { PreToolUse: [] } },
    "cache/srv/.claude-plugin/plugin.json": { name: "srv" },
    "cache/srv/.mcp.json": { mcpServers: { s: {} } },
    "cache/srv/hooks/hooks.json": { hooks: {}, modules: ["./register.tsx"] },
  });
  return root;
}

const project = "/work/app";
const record = (id, scope, installPath, extra = {}) => ({ id, version: "1.0.0", scope, installPath, ...extra });

test("installed plugins carry their dependencies as name@marketplace and what they ship", () => {
  const root = fixture();
  const found = inventory({
    projectDir: project,
    records: [record("impl@m", "user", join(root, "cache/impl")), record("srv@m", "user", join(root, "cache/srv"))],
  });
  assert.deepEqual(found.get("impl@m").dependsOn, ["lib@m", "ext@vendor", "obj@m"]);
  assert.deepEqual(found.get("impl@m").ships, { hooks: true, mod: false, mcp: false, lsp: false });
  assert.deepEqual(found.get("srv@m").ships, { hooks: false, mod: true, mcp: true, lsp: false });
});

test("a project or local install counts only in its own project", () => {
  const found = inventory({
    projectDir: project,
    records: [record("here@m", "local", "/none", { projectPath: project }), record("there@m", "project", "/none", { projectPath: "/work/other" })],
  });
  assert.deepEqual([...found.keys()], ["here@m"]);
});

test("D4: the CLI listing and installed_plugins.json give the same inventory", () => {
  const root = fixture();
  const cli = JSON.stringify([record("impl@m", "user", join(root, "cache/impl"), { enabled: true })]);
  const disk = JSON.stringify({ version: 2, plugins: { "impl@m": [{ scope: "user", installPath: join(root, "cache/impl"), version: "1.0.0" }] } });
  const viaCli = inventory({ projectDir: project, records: recordsFromCli(() => cli) });
  const viaDisk = inventory({ projectDir: project, records: recordsFromDisk("/config", () => disk) });
  assert.deepEqual(viaDisk, viaCli);
});

test("an unreadable listing fails with the reason", () => {
  assert.throws(() => recordsFromCli(() => "not json"), InventoryError);
  assert.throws(() => recordsFromCli(() => new Error("claude: not found")), /claude: not found/);
});

test("AC15: each plugin lists the skills folders that hold a SKILL.md", () => {
  const root = tempDir();
  writeTree(root, {
    "p/.claude-plugin/plugin.json": { name: "p" },
    "p/skills/write/SKILL.md": "---\nname: write\n---\n",
    "p/skills/audit/SKILL.md": "---\nname: audit\n---\n",
    "p/skills/notes/README.md": "not a skill",
  });
  const found = inventory({ projectDir: project, records: [record("p@m", "user", join(root, "p"))] });
  assert.deepEqual(found.get("p@m").skills, ["audit", "write"]);
});

test("known marketplaces are the names claude plugin marketplace list reports", () => {
  assert.deepEqual(knownMarketplaces(() => JSON.stringify([{ name: "a" }, { name: "b", source: "x" }])), new Set(["a", "b"]));
  assert.throws(() => knownMarketplaces(() => "{}"), InventoryError);
});

test("installPlugin asks claude for a user-scope install with no --yes or --marketplace, and passes a failure on", () => {
  const seen = [];
  installPlugin("p@m", (args) => {
    seen.push(args);
    return "";
  });
  assert.deepEqual(seen, [["plugin", "install", "p@m", "--scope", "user"]]);
  assert.throws(() => installPlugin("p@m", () => new Error("claude plugin install exited 1: offline")), /offline/);
});
