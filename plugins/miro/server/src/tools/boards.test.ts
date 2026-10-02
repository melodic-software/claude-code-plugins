import type { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { describe, expect, it } from "vitest";

import { createMiroClients, MISSING_TOKEN_MESSAGE } from "../miro-client.ts";
import { registerBoardTools } from "./boards.ts";

async function connect(api: MiroApi, lowLevel: MiroLowlevelApi) {
  const server = new McpServer({ name: "test", version: "0.0.0" });
  registerBoardTools(server, api, lowLevel);
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-client", version: "0.0.0" });
  await Promise.all([server.connect(serverSide), client.connect(clientSide)]);
  return client;
}

describe("board tools", () => {
  it("call the Miro API unchanged when a token is set", async () => {
    const lowLevel = {
      createBoard: async () => ({ body: { id: "b1", name: "N", viewLink: "https://x/b1" } }),
    } as unknown as MiroLowlevelApi;
    const client = await connect({} as MiroApi, lowLevel);
    const result = await client.callTool({ name: "miro_create_board", arguments: { name: "N" } });
    expect(result.isError).toBeFalsy();
    expect(JSON.stringify(result.content)).toContain("b1");
  });

  it("return the setup guidance as a tool error when the token is unset", async () => {
    const { api, lowLevel } = createMiroClients("");
    const client = await connect(api, lowLevel);
    const result = await client.callTool({ name: "miro_create_board", arguments: { name: "N" } });
    expect(result.isError).toBe(true);
    expect(JSON.stringify(result.content)).toContain(MISSING_TOKEN_MESSAGE.slice(0, 40));
  });
});
