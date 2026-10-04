import type { MiroApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { errorResponse, jsonResponse } from "../response.ts";
import { hasCapability } from "./capability.ts";

export function registerFrameTools(server: McpServer, api: MiroApi): void {
  server.tool(
    "miro_create_frame",
    "Create a frame on a Miro board. Use this to define a layout zone that groups child items such as sticky notes. Returns the frame's { id, type } plus the title, position and geometry as sent; pass that id as parent_id when creating sticky notes inside it, whose x/y are then relative to the frame's top-left corner.",
    {
      board_id: z.string().describe("The board ID"),
      title: z.string().describe("Frame title"),
      x: z
        .number()
        .default(0)
        .describe("X coordinate of the frame's center. Board-center-relative (0 = board center)"),
      y: z
        .number()
        .default(0)
        .describe("Y coordinate of the frame's center. Board-center-relative (0 = board center)"),
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
    "List the items inside one frame. Use this to see what a frame groups, for example to check a zone before adding notes to it. Returns an array of { id, type, position }, positions relative to the frame's top-left corner; it does not return item content (use miro_list_board_items for that). Stops at limit (default 50, max 1000) and gives no sign that more items exist: a result of exactly limit items may be incomplete, so raise limit. Returns an error if frame_id is not a frame.",
    {
      board_id: z.string().describe("The board ID"),
      frame_id: z.string().describe("The frame item ID"),
      limit: z
        .number()
        .min(1)
        .max(1000)
        .default(50)
        .describe("Max items to return (default 50, max 1000)"),
    },
    { readOnlyHint: true, openWorldHint: true },
    async ({ board_id, frame_id, limit }) => {
      const board = await api.getBoard(board_id);
      const frame = await board.getItem(frame_id);
      if (!hasCapability(frame, "getAllItems")) {
        return errorResponse(`Item ${frame_id} is not a frame. Only frames contain child items.`);
      }
      const items: Array<Record<string, unknown>> = [];
      for await (const item of frame.getAllItems()) {
        items.push({
          id: item.id,
          type: item.type,
          ...(item.position ? { position: item.position } : {}),
        });
        if (items.length >= limit) break;
      }
      return jsonResponse(items);
    },
  );
}
