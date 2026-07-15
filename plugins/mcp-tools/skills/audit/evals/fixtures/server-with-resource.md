# Fixture: MCP server with one tool and one resource

TypeScript MCP server excerpt (`@modelcontextprotocol/sdk`). One tool registration and
one resource registration — the resource is present to test scope boundaries, since the
audit evaluates tools only.

```ts
// Tool: list saved snippets.
server.registerTool(
  "list_snippets",
  {
    description:
      "List the saved snippets in the current library. Use this when a user asks what " +
      "snippets exist before inserting or editing one. Returns an array of snippet ids " +
      "and titles.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  async () => {
    const snippets = await store.list();
    return { content: [{ type: "text", text: JSON.stringify(snippets) }] };
  }
);

// Resource: a single saved snippet, addressed by id. NOT a tool.
server.registerResource(
  "snippet",
  new ResourceTemplate("snippet://{id}", { list: undefined }),
  { description: "A single saved snippet, addressed by its id." },
  async (uri, { id }) => {
    const snippet = await store.get(id);
    return { contents: [{ uri: uri.href, text: snippet.body }] };
  }
);
```
