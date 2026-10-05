import type { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: the MCP SDK uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.ts";

const SHARING_ACCESS = ["private", "view", "comment", "edit"] as const;
type SharingAccess = (typeof SHARING_ACCESS)[number];

const sharingAccessEnum = z
  .enum(SHARING_ACCESS)
  .optional()
  .describe("Board link access level. 'view' makes the board public (anyone with link can view)");

// Maps user-facing access level to Miro API inviteToAccountAndBoardLinkAccess
// Ref: https://developers.miro.com/reference/update-board
const INVITE_LEVEL_MAP: Record<SharingAccess, string> = {
  private: "no_access",
  view: "viewer",
  comment: "commenter",
  edit: "editor",
};

function buildSharingPolicy(access: SharingAccess) {
  return {
    sharingPolicy: {
      access,
      inviteToAccountAndBoardLinkAccess: INVITE_LEVEL_MAP[access],
    },
  };
}

export function registerBoardTools(
  server: McpServer,
  api: MiroApi,
  lowLevel: MiroLowlevelApi,
): void {
  server.tool(
    "miro_create_board",
    "Create a new, empty Miro board. Use this to start a new visual collaboration space; to work on a board that already exists, find it with miro_list_boards instead. Returns the new board's id, name and viewLink (the URL to open it). sharing_access sets the board link's access level at creation; omit it to keep Miro's default.",
    {
      name: z.string().describe("Board name"),
      description: z.string().optional().describe("Board description"),
      sharing_access: sharingAccessEnum,
    },
    { destructiveHint: false, openWorldHint: true },
    async ({ name, description, sharing_access }) => {
      const { body: board } = await lowLevel.createBoard({
        name,
        description: description ?? "",
        ...(sharing_access ? { policy: buildSharingPolicy(sharing_access) } : {}),
      });
      return jsonResponse({
        id: board.id,
        name: board.name,
        viewLink: board.viewLink,
      });
    },
  );

  server.tool(
    "miro_list_boards",
    "List Miro boards the token can access. Use this to find a board's ID or check that a board exists before reading or changing it. Returns an array of { id, name, viewLink }. Stops at limit (default 10, max 50) and gives no sign that more boards exist: a result of exactly limit boards may be incomplete, so narrow it with query rather than assuming the board is missing.",
    {
      query: z
        .string()
        .optional()
        .describe("Optional search text to filter boards by name; omit to list all"),
      limit: z
        .number()
        .min(1)
        .max(50)
        .default(10)
        .describe("Max boards to return (default 10, max 50)"),
    },
    { readOnlyHint: true, openWorldHint: true },
    async ({ query, limit }) => {
      const boards: Array<{ id: string; name: string; viewLink: string }> = [];
      for await (const board of api.getAllBoards({ query })) {
        boards.push({
          id: board.id ?? "",
          name: board.name ?? "",
          viewLink: board.viewLink ?? "",
        });
        if (boards.length >= limit) break;
      }
      return jsonResponse(boards);
    },
  );

  server.tool(
    "miro_get_board",
    "Get one Miro board's metadata by ID. Use this to check a board's name, description or when it was last modified. Returns { id, name, description, viewLink, createdAt, modifiedAt }. It does not return sharing settings, owner or members, or the board's items; list items with miro_list_board_items.",
    {
      board_id: z.string().describe("The board ID"),
    },
    { readOnlyHint: true, openWorldHint: true },
    async ({ board_id }) => {
      const board = await api.getBoard(board_id);
      return jsonResponse({
        id: board.id,
        name: board.name,
        description: board.description,
        viewLink: board.viewLink,
        createdAt: board.createdAt,
        modifiedAt: board.modifiedAt,
      });
    },
  );

  server.tool(
    "miro_update_board",
    "Update a Miro board's name, description or link sharing access. Use this to rename a board, change its description or change who can open it by link. Only the fields you pass change; omitted fields keep their current values. Returns the board's { id, name, viewLink, sharingPolicy } after the update.",
    {
      board_id: z.string().describe("The board ID"),
      name: z.string().optional().describe("New board name"),
      description: z.string().optional().describe("New board description"),
      sharing_access: sharingAccessEnum,
    },
    { idempotentHint: true, destructiveHint: false, openWorldHint: true },
    async ({ board_id, name, description, sharing_access }) => {
      const { body: board } = await lowLevel.updateBoard(board_id, {
        ...(name !== undefined ? { name } : {}),
        ...(description !== undefined ? { description } : {}),
        ...(sharing_access ? { policy: buildSharingPolicy(sharing_access) } : {}),
      });
      return jsonResponse({
        id: board.id,
        name: board.name,
        viewLink: board.viewLink,
        sharingPolicy: board.policy?.sharingPolicy,
      });
    },
  );

  server.tool(
    "miro_delete_board",
    'Delete a Miro board and everything on it. Confirm the board ID with miro_list_boards or miro_get_board first; this cannot be undone through these tools. On paid plans, boards go to Trash (restorable via UI within 90 days). Returns { id, status: "deleted" }. To remove one item instead, use miro_delete_item.',
    {
      board_id: z.string().describe("The board ID to delete"),
    },
    { destructiveHint: true, openWorldHint: true },
    async ({ board_id }) => {
      await lowLevel.deleteBoard(board_id);
      return jsonResponse({ id: board_id, status: "deleted" });
    },
  );
}
