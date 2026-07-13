import type { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.js";

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
    "Create a sticky note on a Miro board. Use this for individual notes — for batch creation (up to 20), use miro_bulk_create_sticky_notes instead. Returns the item ID.",
    {
      board_id: z.string().describe("The board ID"),
      content: z.string().describe("Text content for the sticky note"),
      color: z.enum(STICKY_NOTE_COLORS).default("light_yellow").describe("Fill color"),
      x: z
        .number()
        .default(0)
        .describe(
          "X position. Board-center-relative (0 = center) by default; relative to the parent frame's top-left corner when parent_id is set",
        ),
      y: z
        .number()
        .default(0)
        .describe(
          "Y position. Board-center-relative (0 = center) by default; relative to the parent frame's top-left corner when parent_id is set",
        ),
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
    "Update a sticky note's content, color, or position. Use this to modify existing notes without recreating them. Only specified fields are changed — omitted fields keep their current values.",
    {
      board_id: z.string().describe("The board ID"),
      item_id: z.string().describe("The sticky note item ID"),
      content: z.string().optional().describe("New text content"),
      color: z.enum(STICKY_NOTE_COLORS).optional().describe("New fill color"),
      x: z.number().optional().describe("New X position"),
      y: z.number().optional().describe("New Y position"),
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
    "List items on a Miro board. Use this to discover what's on a board before modifying it. Can filter by type (sticky_note, shape, frame, text, connector, etc.). Connectors are retrieved via Miro's separate connectors endpoint — pass type 'connector' to list them (each result carries startItemId/endItemId, the string IDs of the connected items). Returns item IDs, types, data, and positions.",
    {
      board_id: z.string().describe("The board ID"),
      type: z.enum(BOARD_ITEM_TYPES).optional().describe("Filter by item type"),
      limit: z
        .number()
        .min(1)
        .max(1000)
        .default(20)
        .describe("Max items to return (the SDK auto-paginates beyond a single API page)"),
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
    "Delete an item from a Miro board. Use miro_list_board_items first to verify the item ID. Pass the item's type (as returned by miro_list_board_items) so connectors route to Miro's separate connector endpoint; any other type — or omitting it — deletes via the item endpoint.",
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
