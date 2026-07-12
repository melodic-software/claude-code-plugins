import type { MiroApi, MiroLowlevelApi } from "@mirohq/miro-api";
// biome-ignore lint/correctness/noUnresolvedImports: SDK 1.29 uses wildcard subpath exports (./*) which Biome cannot resolve; both tsc and Node runtime resolve correctly.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { jsonResponse } from "../response.js";

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
    "Create a new Miro board. Use this to start a new visual collaboration space. Returns the board ID and view URL.",
    {
      name: z.string().describe("Board name"),
      description: z.string().optional().describe("Board description"),
      sharing_access: sharingAccessEnum,
    },
    { destructiveHint: false, openWorldHint: true },
    async ({ name, description, sharing_access }) => {
      const boardChanges: Record<string, unknown> = {
        name,
        description: description ?? "",
      };
      if (sharing_access) {
        boardChanges["policy"] = buildSharingPolicy(sharing_access);
      }
      const { body: board } = await lowLevel.createBoard(boardChanges);
      return jsonResponse({
        id: board.id,
        name: board.name,
        viewLink: board.viewLink,
      });
    },
  );

  server.tool(
    "miro_list_boards",
    "List accessible Miro boards. Use this to find existing boards or verify a board exists. Returns board IDs, names, and view URLs.",
    {
      query: z.string().optional().describe("Search query to filter boards by name"),
      limit: z.number().min(1).max(50).default(10).describe("Max boards to return"),
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
    "Get details for a specific Miro board. Use this to check board metadata, sharing status, or last modified time. Returns name, description, view URL, and timestamps.",
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
    "Update a Miro board's name, description, or sharing policy. Use this to rename boards, change descriptions, or adjust access levels. Returns the updated board details.",
    {
      board_id: z.string().describe("The board ID"),
      name: z.string().optional().describe("New board name"),
      description: z.string().optional().describe("New board description"),
      sharing_access: sharingAccessEnum,
    },
    { idempotentHint: true, destructiveHint: false, openWorldHint: true },
    async ({ board_id, name, description, sharing_access }) => {
      const boardChanges: Record<string, unknown> = {};
      if (name !== undefined) boardChanges["name"] = name;
      if (description !== undefined) boardChanges["description"] = description;
      if (sharing_access) {
        boardChanges["policy"] = buildSharingPolicy(sharing_access);
      }
      const { body: board } = await lowLevel.updateBoard(board_id, boardChanges);
      return jsonResponse({
        id: board.id,
        name: board.name,
        viewLink: board.viewLink,
        // BoardWithLinks lacks an index signature — double cast needed to access undeclared fields
        sharingPolicy: (board as unknown as Record<string, unknown>)["sharingPolicy"],
      });
    },
  );

  server.tool(
    "miro_delete_board",
    "Permanently delete a Miro board. On paid plans, boards go to Trash (restorable via UI within 90 days). Use miro_list_boards first to verify the board ID.",
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
