import type { MiroApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.js";

/**
 * Default sticky note dimensions in Miro.
 * Square stickies are ~199x199px. Rectangles are wider (~350x199px).
 * Two items overlap when their centers are closer than the item width on both axes.
 */
const DEFAULT_OVERLAP_THRESHOLD = 195;
const TRUNCATE_LENGTH = 60;
const ELLIPSIS = "...";

interface OverlapItem {
  id: string;
  content: string;
  x: number;
  y: number;
}

interface OverlapPair {
  a: OverlapItem;
  b: OverlapItem;
  dx: number;
  dy: number;
}

export function detectOverlaps(items: OverlapItem[], threshold: number): OverlapPair[] {
  const overlaps: OverlapPair[] = [];
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      const a = items[i];
      const b = items[j];
      if (a === undefined || b === undefined) {
        continue;
      }
      const dx = Math.abs(a.x - b.x);
      const dy = Math.abs(a.y - b.y);
      if (dx < threshold && dy < threshold) {
        overlaps.push({ a, b, dx, dy });
      }
    }
  }
  return overlaps;
}

function truncate(s: string): string {
  if (s.length <= TRUNCATE_LENGTH) return s;
  return s.slice(0, TRUNCATE_LENGTH - ELLIPSIS.length) + ELLIPSIS;
}

export function registerOverlapTools(server: McpServer, api: MiroApi): void {
  server.tool(
    "miro_detect_overlaps",
    "Detect overlapping sticky notes on a Miro board. Returns all pairs of stickies whose centers are closer than the threshold on both axes. Sticky notes are ~199px wide, so the default threshold of 195px catches items that visually overlap.",
    {
      board_id: z.string().describe("The board ID"),
      threshold: z
        .number()
        .min(1)
        .max(500)
        .default(DEFAULT_OVERLAP_THRESHOLD)
        .describe("Overlap distance threshold in pixels (default 195 = sticky note width)"),
      max_items: z
        .number()
        .min(1)
        .max(2000)
        .default(500)
        .describe("Maximum sticky notes to scan (limits API pagination calls)"),
    },
    { readOnlyHint: true, openWorldHint: true },
    async ({ board_id, threshold, max_items }) => {
      const board = await api.getBoard(board_id);
      const items: OverlapItem[] = [];

      for await (const item of board.getAllItems({ type: "sticky_note" })) {
        const pos = item.position as { x?: number; y?: number } | undefined;
        const data = item.data as { content?: string } | undefined;
        if (pos?.x != null && pos?.y != null) {
          items.push({
            id: item.id ?? "",
            content: data?.content ?? "",
            x: pos.x,
            y: pos.y,
          });
        }
        if (items.length >= max_items) break;
      }

      const overlaps = detectOverlaps(items, threshold);
      const formatItem = (item: OverlapItem) => ({
        id: item.id,
        content: truncate(item.content),
        x: item.x,
        y: item.y,
      });

      return jsonResponse({
        total_items: items.length,
        overlap_count: overlaps.length,
        overlaps: overlaps.map((o) => ({
          a: formatItem(o.a),
          b: formatItem(o.b),
          dx: Math.round(o.dx),
          dy: Math.round(o.dy),
        })),
      });
    },
  );
}
