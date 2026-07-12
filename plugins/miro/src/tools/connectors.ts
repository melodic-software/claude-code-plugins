import type { MiroLowlevelApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.js";

export function registerConnectorTools(server: McpServer, lowLevel: MiroLowlevelApi): void {
  server.tool(
    "miro_create_connector",
    "Create a connector (line) between two items on a Miro board. Use this to show relationships, flow direction, or dependencies between sticky notes, frames, or other items. Returns the connector ID.",
    {
      board_id: z.string().describe("The board ID"),
      start_item_id: z.string().describe("ID of the item where the connector starts"),
      end_item_id: z.string().describe("ID of the item where the connector ends"),
      caption: z.string().optional().describe("Text label on the connector"),
      stroke_color: z.string().default("#000000").describe("Line color as hex (e.g., #000000)"),
      stroke_style: z.enum(["normal", "dashed", "dotted"]).default("normal").describe("Line style"),
    },
    { destructiveHint: false, openWorldHint: true },
    async ({ board_id, start_item_id, end_item_id, caption, stroke_color, stroke_style }) => {
      const { body: connector } = await lowLevel.createConnector(board_id, {
        startItem: { id: start_item_id },
        endItem: { id: end_item_id },
        ...(caption ? { captions: [{ content: caption, position: "50%" }] } : {}),
        style: {
          strokeColor: stroke_color,
          strokeStyle: stroke_style,
        },
      });
      return jsonResponse({
        id: connector.id,
        type: connector.type,
        startItem: start_item_id,
        endItem: end_item_id,
        caption: caption ?? null,
      });
    },
  );
}
