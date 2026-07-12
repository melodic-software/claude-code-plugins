import type { MiroApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { errorResponse, jsonResponse } from "../response.js";

const TAG_COLORS = [
  "red",
  "light_green",
  "cyan",
  "yellow",
  "magenta",
  "green",
  "blue",
  "gray",
  "violet",
  "dark_green",
  "dark_blue",
  "orange",
] as const;

export function registerTagTools(server: McpServer, api: MiroApi): void {
  server.tool(
    "miro_create_tag",
    "Create a tag on a Miro board for categorizing items. Use this before miro_attach_tag. Tags are board-scoped — create once, attach to many items. Returns the tag ID.",
    {
      board_id: z.string().describe("The board ID"),
      title: z.string().describe("Tag title text"),
      color: z.enum(TAG_COLORS).default("blue").describe("Tag color"),
    },
    { destructiveHint: false, openWorldHint: true },
    async ({ board_id, title, color }) => {
      const board = await api.getBoard(board_id);
      const tag = await board.createTag({ title, fillColor: color });
      return jsonResponse({ id: tag.id, title: tag.title, color });
    },
  );

  server.tool(
    "miro_attach_tag",
    "Attach an existing tag to a board item. Use miro_create_tag first to create the tag, then attach it to sticky notes, cards, or other taggable items. Idempotent — attaching the same tag twice is safe.",
    {
      board_id: z.string().describe("The board ID"),
      item_id: z.string().describe("The item ID to tag"),
      tag_id: z.string().describe("The tag ID to attach"),
    },
    { idempotentHint: true, destructiveHint: false, openWorldHint: true },
    async ({ board_id, item_id, tag_id }) => {
      const board = await api.getBoard(board_id);
      const item = await board.getItem(item_id);
      if (!item || !("attachTag" in item) || typeof item.attachTag !== "function") {
        return errorResponse(
          `Item ${item_id} does not support tags. Only sticky notes, cards, and similar items can have tags attached.`,
        );
      }
      await item.attachTag(tag_id);
      return jsonResponse({ item_id, tag_id, status: "attached" });
    },
  );
}
