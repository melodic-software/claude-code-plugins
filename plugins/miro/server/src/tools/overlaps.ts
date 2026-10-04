import type { MiroApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.ts";

/**
 * Miro square stickies are ~199x199px, rectangles ~350x199px. Two items overlap when
 * their centers are closer than this on both axes.
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
    const a = items[i];
    if (a === undefined) {
      continue;
    }
    for (let j = i + 1; j < items.length; j++) {
      const b = items[j];
      if (b === undefined) {
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

function formatItem(item: OverlapItem) {
  return {
    id: item.id,
    content: truncate(item.content),
    x: item.x,
    y: item.y,
  };
}

export function registerOverlapTools(server: McpServer, api: MiroApi): void {
  server.tool(
    "miro_detect_overlaps",
    "Find sticky notes that cover each other on a Miro board. Use this after placing many notes, for example after miro_bulk_create_sticky_notes, then move the overlapping ones with miro_update_sticky_note. Returns { total_items, overlap_count, overlaps }, each overlap a pair a/b of { id, content, x, y } (content cut to 60 characters) with their center distances dx and dy. A pair overlaps when its centers are closer than threshold on both axes. Scans at most max_items notes (default 500, max 2000) and does not say whether more exist: if total_items equals max_items, raise max_items if it is below 2000; at 2000, notes past the cap are not checked, so overlaps among them go unreported. The default threshold of 195px fits square notes (~199px wide); raise it on boards with many rectangle notes (~350px wide).",
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
        .describe("Maximum sticky notes to scan (default 500, max 2000)"),
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
