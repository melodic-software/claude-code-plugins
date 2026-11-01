#!/usr/bin/env bash
# Stages a Node MCP server that speaks stdio, with unit-level tests of its tool
# handlers and no protocol-level check.
set -euo pipefail

mkdir -p src test

cat >package.json <<'JSON'
{
  "name": "ticket-mcp",
  "version": "0.3.0",
  "type": "module",
  "main": "dist/index.js",
  "scripts": {
    "build": "mkdir -p dist && cp src/*.js dist/",
    "test": "node --test test/"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.12.0"
  }
}
JSON

cat >src/tools.js <<'JS'
export const tools = {
  list_tickets: async ({ status }) => [{ id: "T-1", status: status ?? "open" }],
  close_ticket: async ({ id }) => ({ id, status: "closed" }),
};
JS

cat >src/index.js <<'JS'
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { tools } from "./tools.js";

const server = new Server({ name: "ticket-mcp", version: "0.3.0" }, { capabilities: {} });

for (const [name, handler] of Object.entries(tools)) {
  server.tool?.(name, handler);
}

await server.connect(new StdioServerTransport());
JS

cat >test/tools.spec.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { tools } from "../src/tools.js";

test("close_ticket marks the ticket closed", async () => {
  assert.deepEqual(await tools.close_ticket({ id: "T-1" }), { id: "T-1", status: "closed" });
});
JS

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add ticket MCP server"
printf '/.*\n' >>.git/info/exclude
