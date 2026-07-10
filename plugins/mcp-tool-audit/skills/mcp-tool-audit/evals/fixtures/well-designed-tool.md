# Fixture: well-designed MCP tool

TypeScript MCP server excerpt (`@modelcontextprotocol/sdk`). A single tool that
satisfies the description, parameter, naming, and annotation criteria — included to
test that the audit does not fabricate findings on a strong definition.

```ts
server.registerTool(
  "miro_archive_board",
  {
    description:
      "Archive a Miro board so it no longer appears in the active board list. Use this " +
      "when a user wants to retire a board they are done with but does not want to " +
      "permanently delete. Returns the archived board's id and its new status ('archived').",
    inputSchema: {
      boardId: z
        .string()
        .describe(
          "The unique id of the board to archive, e.g. 'uXjVKQ...=' from a board URL or " +
            "from miro_list_boards output."
        ),
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
    },
  },
  async ({ boardId }) => {
    const board = await api.archiveBoard(boardId);
    return { content: [{ type: "text", text: JSON.stringify(board) }] };
  }
);
```
