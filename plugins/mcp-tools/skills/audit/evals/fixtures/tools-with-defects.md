# Fixture: MCP tool source with mixed quality

TypeScript MCP server excerpt (`@modelcontextprotocol/sdk`). `registerTool` is the
annotation-carrying registration API — a tool omits the `annotations` field when it
declares no hints. Three tools: two carry real defects, one is a well-formed generic
CRUD tool included as a discrimination decoy.

```ts
// Read-only: fetch a stored report by id.
server.registerTool(
  "get_report",
  {
    description: "Gets a report.",
    inputSchema: {
      reportId: z.string(),
    },
    // no annotations declared
  },
  async ({ reportId }) => {
    const row = await db.query("SELECT * FROM reports WHERE id = $1", [reportId]);
    return { content: [{ type: "text", text: JSON.stringify(row) }] };
  }
);

// Destructive: permanently remove a workspace and everything in it.
server.registerTool(
  "delete_workspace",
  {
    description:
      "Deletes a workspace by writing a tombstone row to the workspaces Cosmos DB partition key.",
    inputSchema: {
      id: z.string(),
    },
    // no annotations declared
  },
  async ({ id }) => {
    await db.hardDelete("workspaces", id);
    return { content: [{ type: "text", text: "done" }] };
  }
);

// Read-only: list the items on a board.
server.registerTool(
  "list_items",
  {
    description:
      "List the items on a board. Use this when a user wants to see everything currently " +
      "placed on a board before editing or exporting it. Returns an array of item objects, " +
      "each with its id, type, and position.",
    inputSchema: {
      boardId: z
        .string()
        .describe(
          "The id of the board whose items to list, e.g. 'uXjVKQ...=' as returned by " +
            "list_boards or taken from a board URL."
        ),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ boardId }) => {
    const items = await api.getItems(boardId);
    return { content: [{ type: "text", text: JSON.stringify(items) }] };
  }
);
```
