# Fixture: `x-mcp-header` parameters (C20)

One TypeScript server (`@modelcontextprotocol/sdk`) whose tools attach `x-mcp-header` to
parameter schemas through Zod `.meta()`. One tool declares it validly, one breaks a constraint,
one marks a secret, and one declares none.

```ts
// Valid: a string parameter mirrored as "Region".
server.registerTool(
  "run_query",
  {
    description:
      "Run a read-only SQL query against the analytics warehouse. Use this to answer questions " +
      "about historical usage. Returns the result rows as JSON.",
    inputSchema: {
      region: z.string().describe("Warehouse region, e.g. 'us-west1'.").meta({ "x-mcp-header": "Region" }),
      query: z.string().describe("The SQL SELECT statement to run."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ region, query }) => ({ content: [{ type: "text", text: await wh.run(region, query) }] })
);

// Invalid: the keyword sits on a `number` parameter, and two values differ only by case.
server.registerTool(
  "resize_cluster",
  {
    description:
      "Resize a warehouse cluster. Use this when a human asks to scale capacity up or down. " +
      "Returns the cluster's new node count.",
    inputSchema: {
      cluster: z.string().describe("Cluster id, e.g. 'wh-prod-1'.").meta({ "x-mcp-header": "Cluster" }),
      scale: z.number().describe("Scale factor, e.g. 1.5.").meta({ "x-mcp-header": "Scale" }),
      zone: z.string().describe("Zone id, e.g. 'us-west1-a'.").meta({ "x-mcp-header": "cluster" }),
    },
  },
  async ({ cluster, scale }) => ({ content: [{ type: "text", text: String(await wh.resize(cluster, scale)) }] })
);

// Sensitive: an API key mirrored into a header.
server.registerTool(
  "export_report",
  {
    description:
      "Export a saved report to the partner's storage. Use this when a human asks to share a " +
      "report externally. Returns the export's URL.",
    inputSchema: {
      reportId: z.string().describe("Saved report id, e.g. 'rpt_42'."),
      partnerApiKey: z.string().describe("The partner's API key.").meta({ "x-mcp-header": "Partner-Key" }),
    },
  },
  async ({ reportId, partnerApiKey }) => ({ content: [{ type: "text", text: await exp.run(reportId, partnerApiKey) }] })
);

// No x-mcp-header at all.
server.registerTool(
  "list_reports",
  {
    description:
      "List saved reports. Use this to find a report id before exporting it. Returns id and " +
      "title for each report.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  async () => ({ content: [{ type: "text", text: JSON.stringify(await reports.list()) }] })
);
```
