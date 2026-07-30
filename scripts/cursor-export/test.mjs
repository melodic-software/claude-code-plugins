#!/usr/bin/env node

// Unit tests for the Cursor companion-host export.
// Driven by:
//   https://cursor.com/docs/reference/plugins (variables + mcp.json + hooks discovery)
//   https://cursor.com/docs/hooks (version + hooks object)
//   https://cursor.com/docs/reference/third-party-hooks (Claude settings ≠ plugin hooks)
//
//   node scripts/cursor-export/test.mjs

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cursorDescription } from "./description.mjs";
import { buildCursorMcpBundle, mcpNeedsCursorPort } from "./mcp.mjs";
import { buildCursorPlugin, EMPTY_CURSOR_HOOKS } from "./plugin.mjs";

let passed = 0;
let failed = 0;

function ok(name) {
  console.log(`ok: ${name}`);
  passed += 1;
}

function fail(name, detail) {
  console.error(`FAIL: ${name}: ${detail}`);
  failed += 1;
}

function assert(name, condition, detail = "assertion failed") {
  if (condition) ok(name);
  else fail(name, detail);
}

assert(
  "mcpNeedsCursorPort detects user_config",
  mcpNeedsCursorPort('{"url":"${user_config.api_key}"}'),
);
assert(
  "mcpNeedsCursorPort detects CLAUDE_PLUGIN_ROOT",
  mcpNeedsCursorPort('{"args":["${CLAUDE_PLUGIN_ROOT}/dist/x.js"]}'),
);
assert(
  "mcpNeedsCursorPort ignores clean config",
  !mcpNeedsCursorPort('{"url":"https://example.com"}'),
);

{
  const dir = mkdtempSync(join(tmpdir(), "cursor-mcp-"));
  try {
    writeFileSync(
      join(dir, ".mcp.json"),
      JSON.stringify({
        mcpServers: {
          demo: {
            type: "http",
            url: "https://example.com/mcp",
            headers: { Authorization: "Bearer ${user_config.demo_api_key}" },
          },
        },
      }),
    );
    const bundle = buildCursorMcpBundle(dir, {
      userConfig: {
        demo_api_key: {
          type: "string",
          title: "Demo API key",
          description:
            "Stored by Claude Code in secure credential storage, never settings.json.",
          required: true,
        },
      },
    });
    assert("buildCursorMcpBundle returns bundle", Boolean(bundle));
    assert(
      "ports user_config to ${DEMO_API_KEY}",
      bundle.mcpFile.mcpServers.demo.headers.Authorization ===
        "Bearer ${DEMO_API_KEY}",
    );
    assert(
      "declares variables schema per Cursor docs",
      bundle.variables?.type === "object" &&
        bundle.variables.properties.DEMO_API_KEY?.type === "string" &&
        bundle.variables.required.includes("DEMO_API_KEY"),
    );
    assert(
      "rewrites Claude credential storage wording",
      /Plugins → Configure/.test(
        bundle.variables.properties.DEMO_API_KEY.description,
      ) &&
        !bundle.variables.properties.DEMO_API_KEY.description.includes(
          "Configure.json",
        ),
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

{
  const dir = mkdtempSync(join(tmpdir(), "cursor-mcp-root-"));
  try {
    writeFileSync(
      join(dir, ".mcp.json"),
      JSON.stringify({
        mcpServers: {
          local: {
            command: "node",
            args: ["${CLAUDE_PLUGIN_ROOT}/dist/index.min.js"],
            env: { TOKEN: "${user_config.miro_api_token}" },
          },
        },
      }),
    );
    const bundle = buildCursorMcpBundle(dir, {
      userConfig: {
        miro_api_token: { type: "string", title: "Token", required: true },
      },
    });
    assert(
      "ports CLAUDE_PLUGIN_ROOT to relative ./",
      bundle.mcpFile.mcpServers.local.args[0] === "./dist/index.min.js",
    );
    assert(
      "ports env user_config to ${MIRO_API_TOKEN}",
      bundle.mcpFile.mcpServers.local.env.TOKEN === "${MIRO_API_TOKEN}",
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

{
  const dir = mkdtempSync(join(tmpdir(), "cursor-mcp-none-"));
  try {
    assert(
      "buildCursorMcpBundle null when no .mcp.json",
      buildCursorMcpBundle(dir, {}) === null,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

{
  const withHooks = cursorDescription(
    "Auto-format and lint Markdown on edit via markdownlint-cli2.",
    { hasClaudePluginHooks: true, hasCursorMcp: false },
  );
  assert(
    "hook plugins get Cursor note citing third-party hooks path",
    withHooks.includes("Cursor note:") &&
      withHooks.includes(".claude/settings.json") &&
      withHooks.includes("third-party"),
  );

  const withCreds = cursorDescription(
    "Remote MCP. Credential entered once through Claude Code's native masked userConfig prompt and stored in secure credential storage.",
    { hasClaudePluginHooks: false, hasCursorMcp: true },
  );
  assert(
    "userConfig credential copy rewritten to Plugins → Configure",
    withCreds.includes("Plugins → Configure") &&
      !withCreds.includes("masked userConfig"),
  );
}

{
  const dir = mkdtempSync(join(tmpdir(), "cursor-plugin-hooks-"));
  try {
    mkdirSync(join(dir, "hooks"), { recursive: true });
    writeFileSync(
      join(dir, "hooks", "hooks.json"),
      JSON.stringify({ hooks: { PostToolUse: [] } }),
    );
    const { plugin, hooksStub, mcpBundle } = buildCursorPlugin(
      {
        name: "markdown-format",
        description: "Auto-format Markdown on edit.",
      },
      dir,
    );
    assert(
      "Claude hooks → Cursor plugin.json hooks points at stub",
      plugin.hooks === "./.cursor-plugin/hooks.json",
    );
    assert(
      "empty Cursor hooks stub uses documented version+hooks shape",
      hooksStub?.version === EMPTY_CURSOR_HOOKS.version &&
        Object.keys(hooksStub.hooks).length === 0,
    );
    assert("no MCP bundle without .mcp.json", mcpBundle === null);
    assert(
      "description does not promise Claude plugin hooks as Cursor hooks",
      plugin.description.includes("Cursor note:"),
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
