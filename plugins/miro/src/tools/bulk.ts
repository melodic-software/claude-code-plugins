import type { MiroApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.js";
import { buildStickyNotePayload, STICKY_NOTE_COLORS, STICKY_NOTE_SHAPES } from "./sticky-notes.js";

export const stickyNoteSchema = z.object({
  content: z.string().describe("Text content"),
  color: z.enum(STICKY_NOTE_COLORS).default("light_yellow").describe("Fill color name"),
  shape: z
    .enum(STICKY_NOTE_SHAPES)
    .default("square")
    .describe("Sticky note shape. Use rectangle for Read Models, External Systems, Pivotal Events"),
  x: z
    .number()
    .describe(
      "X position. Board-center-relative (0 = center) by default; relative to the parent frame's top-left corner when parent_id is set",
    ),
  y: z
    .number()
    .describe(
      "Y position. Board-center-relative (0 = center) by default; relative to the parent frame's top-left corner when parent_id is set",
    ),
});

export function registerBulkTools(server: McpServer, api: MiroApi): void {
  server.tool(
    "miro_bulk_create_sticky_notes",
    "Create multiple sticky notes at once (max 20 per call). Use this instead of miro_create_sticky_note when placing many notes — faster and rate-limit aware. Notes are created sequentially with no rollback: if a later note fails, the earlier ones remain on the board. Returns the count and IDs of created items.",
    {
      board_id: z.string().describe("The board ID"),
      sticky_notes: z
        .array(stickyNoteSchema)
        .min(1)
        .max(20)
        .describe("Array of sticky notes to create (max 20)"),
      parent_id: z
        .string()
        .optional()
        .describe(
          "Parent frame ID to place all stickies inside. When set, each note's x/y is interpreted relative to the frame's top-left corner, not the board center",
        ),
    },
    { destructiveHint: false, openWorldHint: true },
    async ({ board_id, sticky_notes, parent_id }) => {
      const board = await api.getBoard(board_id);
      const created: Array<{ id: string; content: string; color: string }> = [];

      for (const note of sticky_notes) {
        // biome-ignore lint/performance/noAwaitInLoops: sequential to respect Miro API rate limits
        const sticky = await board.createStickyNoteItem(
          buildStickyNotePayload({
            content: note.content,
            shape: note.shape,
            color: note.color,
            x: note.x,
            y: note.y,
            parentId: parent_id,
          }),
        );
        created.push({
          id: sticky.id ?? "",
          content: note.content,
          color: note.color,
        });
      }

      return jsonResponse({
        count: created.length,
        items: created,
      });
    },
  );
}
