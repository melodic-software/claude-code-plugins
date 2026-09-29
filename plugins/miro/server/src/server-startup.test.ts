import { fileURLToPath } from "node:url";

// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { describe, expect, it } from "vitest";

const bundle = fileURLToPath(new URL("../dist/index.min.js", import.meta.url));

async function callListBoards(env: Record<string, string>) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [bundle],
    env: { PATH: process.env["PATH"] ?? "", ...env },
  });
  const client = new Client({ name: "startup-test", version: "0.0.0" });
  await client.connect(transport);
  try {
    return await client.callTool({ name: "miro_list_boards", arguments: {} });
  } finally {
    await client.close();
  }
}

describe("committed bundle started without a usable token", () => {
  const shapes: Record<string, Record<string, string>> = {
    "variable absent": {},
    "empty string": { MIRO_API_TOKEN: "" },
    // biome-ignore lint/suspicious/noTemplateCurlyInString: the literal unexpanded user_config text is the input under test.
    "unexpanded placeholder": { MIRO_API_TOKEN: "${user_config.miro_api_token}" },
  };

  it.each(Object.entries(shapes))(
    "starts and returns setup guidance: %s",
    async (_name, env) => {
      const result = await callListBoards(env);
      expect(result.isError).toBe(true);
      expect(JSON.stringify(result.content)).toContain("/plugin configure miro@melodic-software");
    },
    20_000,
  );
});
