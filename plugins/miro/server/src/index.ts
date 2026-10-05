// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createMiroClients } from "./miro-client.ts";
import { registerBoardTools } from "./tools/boards.ts";
import { registerBulkTools } from "./tools/bulk.ts";
import { registerConnectorTools } from "./tools/connectors.ts";
import { registerFrameTools } from "./tools/frames.ts";
import { registerOverlapTools } from "./tools/overlaps.ts";
import { registerStickyNoteTools } from "./tools/sticky-notes.ts";
import { registerTagTools } from "./tools/tags.ts";

const server = new McpServer(
  { name: "miro-mcp", version: "0.2.2" },
  {
    instructions:
      "Reads and edits Miro boards: boards, sticky notes, frames, tags and connectors, " +
      "plus bulk sticky-note creation and overlap detection. " +
      "Search these tools when the user names a Miro board or asks to lay out an " +
      "EventStorming, brainstorming or diagram board in Miro. " +
      "Every call needs a Miro API token; without one, the tool returns an error " +
      "that explains how to set it.",
  },
);

const { api, lowLevel } = createMiroClients();

registerBoardTools(server, api, lowLevel);
registerStickyNoteTools(server, api, lowLevel);
registerFrameTools(server, api);
registerTagTools(server, api);
registerConnectorTools(server, lowLevel);
registerBulkTools(server, api);
registerOverlapTools(server, api);

const transport = new StdioServerTransport();
await server.connect(transport);
