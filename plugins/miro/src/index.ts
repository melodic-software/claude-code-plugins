// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createMiroClients } from "./miro-client.js";
import { registerBoardTools } from "./tools/boards.js";
import { registerBulkTools } from "./tools/bulk.js";
import { registerConnectorTools } from "./tools/connectors.js";
import { registerFrameTools } from "./tools/frames.js";
import { registerOverlapTools } from "./tools/overlaps.js";
import { registerStickyNoteTools } from "./tools/sticky-notes.js";
import { registerTagTools } from "./tools/tags.js";

const server = new McpServer(
  { name: "miro-mcp", version: "0.1.2" },
  {
    instructions:
      "Miro board management for visual collaboration. " +
      "Use these tools to create and manage boards, sticky notes, frames, " +
      "tags, and connectors for EventStorming, brainstorming, and diagramming.",
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
