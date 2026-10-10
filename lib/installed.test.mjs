import { strict as assert } from "node:assert";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { installed } from "./installed.mjs";

const scratch = mkdtempSync(join(tmpdir(), "installed-lib-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

const ROWS = [{ id: "dovetail", kind: "mcp", detect: "dovetail", account: "login" }];
/** installed() over ROWS with the given plugin reader; returns the result and how often the MCP reader ran. */
function run(pluginList, mcpText = "dovetail: https://mcp.example.test (HTTP) - ✔ Connected\n") {
  let mcpCalls = 0;
  const result = installed(ROWS, {
    pluginRoot: scratch,
    home: scratch,
    projectDir: scratch,
    projectMcpServers: [],
    pluginList,
    mcpList: () => {
      mcpCalls++;
      return mcpText;
    },
  });
  return { result, mcpCalls };
}

test("the MCP reader is not called when the plugin reader returns an Error", () => {
  const { result, mcpCalls } = run(() => new Error("claude plugin list --json failed: exit 1"));
  assert.equal(mcpCalls, 0);
  assert.equal(result.installed, null);
  assert.equal(result.reason, "claude plugin list --json failed: exit 1");
});

test("the MCP reader is not called when the plugin list is unparsable", () => {
  const { result, mcpCalls } = run(() => "{not json");
  assert.equal(mcpCalls, 0);
  assert.equal(result.installed, null);
  assert.match(result.reason, /^unreadable plugin list/);
});

test("a parsed plugin list reads the MCP list once and detects a connected server", () => {
  const { result, mcpCalls } = run(() => "[]");
  assert.equal(mcpCalls, 1);
  assert.deepEqual(result.installed, ["dovetail"]);
  assert.deepEqual(result.reachable, { dovetail: true });
});

test("an MCP reader Error nulls installed with its message", () => {
  let mcpCalls = 0;
  const result = installed(ROWS, {
    pluginRoot: scratch,
    home: scratch,
    projectDir: scratch,
    projectMcpServers: [],
    pluginList: () => "[]",
    mcpList: () => {
      mcpCalls++;
      return new Error("claude mcp list failed: exit 2");
    },
  });
  assert.equal(mcpCalls, 1);
  assert.equal(result.installed, null);
  assert.equal(result.reason, "claude mcp list failed: exit 2");
});
