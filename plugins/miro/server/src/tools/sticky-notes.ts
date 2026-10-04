import type { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.ts";

export const STICKY_NOTE_COLORS = [
  "gray",
  "light_yellow",
  "yellow",
  "orange",
  "light_green",
  "green",
  "dark_green",
  "cyan",
  "light_pink",
  "pink",
  "violet",
  "red",
  "light_blue",
  "blue",
  "dark_blue",
  "black",
] as const;

export const STICKY_NOTE_SHAPES = ["square", "rectangle"] as const;

export const POSITION_X_DESCRIPTION =
  "X coordinate of the note's center. Board-center-relative (0 = board center) by default; relative to the parent frame's top-left corner when the note is in a frame (parent_id)";
export const POSITION_Y_DESCRIPTION =
  "Y coordinate of the note's center. Board-center-relative (0 = board center) by default; relative to the parent frame's top-left corner when the note is in a frame (parent_id)";

const BOARD_ITEM_TYPES = [
  "sticky_note",
  "shape",
  "frame",
  "text",
  "card",
  "connector",
  "image",
  "document",
  "app_card",
] as const;

interface StickyNotePayloadInput {
  content: string;
  shape: (typeof STICKY_NOTE_SHAPES)[number];
  color: (typeof STICKY_NOTE_COLORS)[number];
  x: number;
  y: number;
  parentId?: string | undefined;
}

export function buildStickyNotePayload(input: StickyNotePayloadInput) {
  return {
    data: { content: input.content, shape: input.shape },
    style: {
      fillColor: input.color,
      textAlign: "center" as const,
      textAlignVertical: "middle" as const,
    },
    position: { x: input.x, y: input.y },
    ...(input.parentId ? { parent: { id: input.parentId } } : {}),
  };
}

export function registerStickyNoteTools(
  server: McpServer,
  api: MiroApi,
  lowLevel: MiroLowlevelApi,
): void {
  server.tool(
    "miro_create_sticky_note",
    "Create one sticky note on a Miro board, optionally inside a frame (parent_id). Use this for a single note; to place several, use miro_bulk_create_sticky_notes (up to 20 per call). Returns the new note's { id, type } plus the content, color and position as sent. Run miro_detect_overlaps after placing many notes to find ones that cover each other.",
    {
      board_id: z.string().describe("The board ID"),
      content: z.string().describe("Text content for the sticky note"),
      color: z.enum(STICKY_NOTE_COLORS).default("light_yellow").describe("Fill color"),
      x: z.number().default(0).describe(POSITION_X_DESCRIPTION),
      y: z.number().default(0).describe(POSITION_Y_DESCRIPTION),
      shape: z.enum(STICKY_NOTE_SHAPES).default("square").describe("Sticky note shape"),
      parent_id: z
        .string()
        .optional()
        .describe(
          "Parent frame ID to place the sticky inside. When set, x/y are interpreted relative to the frame's top-left corner, not the board center",
        ),
    },
    { destructiveHint: false, openWorldHint: true },
    async ({ board_id, content, color, x, y, shape, parent_id }) => {
      const board = await api.getBoard(board_id);
      const sticky = await board.createStickyNoteItem(
        buildStickyNotePayload({ content, shape, color, x, y, parentId: parent_id }),
      );
      return jsonResponse({
        id: sticky.id,
        type: sticky.type,
        content,
        color,
        position: { x, y },
      });
    },
  );

  server.tool(
    "miro_update_sticky_note",
    "Update an existing sticky note's content, color or position. Use this to change a note in place instead of deleting and recreating it. Only the fields you pass change; omitted fields keep their current values. Shape cannot be changed here: delete the note and create it again with the new shape. Returns { id, status: \"updated\" }, not the note's new state; read it back with miro_list_board_items.",
    {
      board_id: z.string().describe("The board ID"),
      item_id: z.string().describe("The sticky note item ID"),
      content: z.string().optional().describe("New text content"),
      color: z.enum(STICKY_NOTE_COLORS).optional().describe("New fill color"),
      x: z.number().optional().describe(POSITION_X_DESCRIPTION),
      y: z.number().optional().describe(POSITION_Y_DESCRIPTION),
    },
    { idempotentHint: true, destructiveHint: false, openWorldHint: true },
    async ({ board_id, item_id, content, color, x, y }) => {
      const updatePayload: Record<string, unknown> = {};
      if (content !== undefined) {
        updatePayload["data"] = { content };
      }
      if (color !== undefined) {
        updatePayload["style"] = { fillColor: color };
      }
      if (x !== undefined || y !== undefined) {
        updatePayload["position"] = {
          ...(x !== undefined ? { x } : {}),
          ...(y !== undefined ? { y } : {}),
        };
      }
      await lowLevel.updateStickyNoteItem(board_id, item_id, updatePayload);
      return jsonResponse({ id: item_id, status: "updated" });
    },
  );

  server.tool(
    "miro_list_board_items",
    "List items on a Miro board. Use this to see what is on a board, and to get item IDs, before changing or deleting items. Returns an array of { id, type, data, position }, with data and position only when Miro sends them. Stops at limit (default 20, max 1000) and gives no sign that more items exist: a result of exactly limit items may be incomplete, so filter with type or raise limit. Connectors are listed only when type is 'connector'; each then carries startItemId and endItemId, the IDs of the items it joins.",
    {
      board_id: z.string().describe("The board ID"),
      type: z
        .enum(BOARD_ITEM_TYPES)
        .optional()
        .describe(
          "Optional item type to list. Omit to list every type except connectors; pass 'connector' to list connectors",
        ),
      limit: z
        .number()
        .min(1)
        .max(1000)
        .default(20)
        .describe("Max items to return (default 20, max 1000)"),
    },
    { readOnlyHint: true, openWorldHint: true },
    async ({ board_id, type, limit }) => {
      const board = await api.getBoard(board_id);
      const items: Array<Record<string, unknown>> = [];
      if (type === "connector") {
        // Connectors are not returned by the items endpoint; Miro exposes them separately.
        for await (const connector of board.getAllConnectors()) {
          items.push({
            id: connector.id,
            type: connector.type ?? "connector",
            ...(connector.startItem?.id ? { startItemId: connector.startItem.id } : {}),
            ...(connector.endItem?.id ? { endItemId: connector.endItem.id } : {}),
          });
          if (items.length >= limit) break;
        }
      } else {
        for await (const item of board.getAllItems({ type })) {
          items.push({
            id: item.id,
            type: item.type,
            ...(item.data && typeof item.data === "object" ? { data: item.data } : {}),
            ...(item.position ? { position: item.position } : {}),
          });
          if (items.length >= limit) break;
        }
      }
      return jsonResponse(items);
    },
  );

  server.tool(
    "miro_delete_item",
    "Delete one item from a Miro board. Confirm the item ID with miro_list_board_items first. Pass type 'connector' to delete a connector; any other type, or none, deletes through the item endpoint, which does not reach connectors. Returns { id, status: \"deleted\" }. To delete a whole board, use miro_delete_board.",
    {
      board_id: z.string().describe("The board ID"),
      item_id: z.string().describe("The item ID to delete"),
      type: z
        .enum(BOARD_ITEM_TYPES)
        .optional()
        .describe(
          "Item type, as returned by miro_list_board_items. 'connector' routes to Miro's separate connector-delete endpoint; every other type (sticky_note, shape, frame, …) uses the item-delete endpoint",
        ),
    },
    { destructiveHint: true, openWorldHint: true },
    async ({ board_id, item_id, type }) => {
      if (type === "connector") {
        await lowLevel.deleteConnector(board_id, item_id);
      } else {
        await lowLevel.deleteItem(board_id, item_id);
      }
      return jsonResponse({ id: item_id, status: "deleted" });
    },
  );
}
