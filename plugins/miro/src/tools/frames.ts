import type { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.js";

export function registerFrameTools(
  server: McpServer,
  api: MiroApi,
  lowLevel: MiroLowlevelApi,
): void {
  server.tool(
    "miro_create_frame",
    "Create a frame on a Miro board. Use this to define layout zones that group child items (sticky notes, shapes). Use the returned frame ID as parent_id when creating sticky notes inside it.",
    {
      board_id: z.string().describe("The board ID"),
      title: z.string().describe("Frame title"),
      x: z.number().default(0).describe("X position on the board"),
      y: z.number().default(0).describe("Y position on the board"),
      width: z.number().default(800).describe("Frame width in pixels"),
      height: z.number().default(600).describe("Frame height in pixels"),
    },
    { destructiveHint: false, openWorldHint: true },
    async ({ board_id, title, x, y, width, height }) => {
      const board = await api.getBoard(board_id);
      const frame = await board.createFrameItem({
        data: { title, format: "custom" },
        position: { x, y },
        geometry: { width, height },
      });
      return jsonResponse({
        id: frame.id,
        type: frame.type,
        title,
        position: { x, y },
        geometry: { width, height },
      });
    },
  );

  server.tool(
    "miro_get_frame_items",
    "List all items inside a specific frame. Use this to see what's grouped within a frame. Returns item IDs, types, and positions relative to the frame.",
    {
      board_id: z.string().describe("The board ID"),
      frame_id: z.string().describe("The frame item ID"),
      limit: z.number().min(1).max(50).default(50).describe("Max items to return per page"),
    },
    { readOnlyHint: true, openWorldHint: true },
    async ({ board_id, frame_id, limit }) => {
      const result = await lowLevel.getItemsWithinFrame(board_id, frame_id, {
        limit: limit.toString(),
      });
      const items = (result.body?.data ?? []).map((item) => ({
        id: item.id,
        type: item.type,
        position: item.position,
      }));
      return jsonResponse(items);
    },
  );
}
