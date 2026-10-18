# Fixture: MCP server whose tool description and server instructions run past 2,048 characters

TypeScript MCP server excerpt (`@modelcontextprotocol/sdk`). One server construction site and one tool
registration. The server `instructions` field and the `export_ledger` tool description are each over
2,048 characters, written as single-line string literals so the length is unambiguous. Everything else
about the tool is sound: the description opens with what, when and returns, the parameter is described,
and the annotations are present. The only defect is length, so the audit's C4 finding is the one under test.

```ts
// Server construction site: the `instructions` field below is over 2,048 characters.
const server = new McpServer(
  { name: "ledger-server", version: "1.0.0" },
  {
    instructions:
      "Use this server to read and export accounting ledgers for a single company. Start with export_ledger when the user asks for a ledger, a trial balance, or a transaction history, and always pass the company id the user named rather than guessing one. Every tool here is read-only and never changes a ledger. Ledger exports can be large, so prefer a narrow date range over a full-year export unless the user explicitly asks for the whole year. The notes that follow describe the conventions this server follows, and they are reference material rather than steps to carry out. Amounts are always reported in the ledger's base currency, in minor units, so an amount of 1250 in a USD ledger means twelve dollars and fifty cents. Dates are ISO 8601 calendar dates in the company's local time zone. Accounts follow the company's own chart of accounts, and the account code is a string that may carry leading zeros, so never treat it as a number. A closed period is still readable, but entries posted after the close are flagged with a late-posting marker and should be mentioned when summarizing. Reversal entries point back at the entry they reverse through the reversesEntryId field, and a reversed entry stays in the export with a reversed marker instead of being removed. Intercompany transfers appear once in each company's ledger, with the counterparty company id in the memo, and the two sides always net to zero across the group. Rounding differences smaller than one minor unit are posted to the rounding account and are not errors. Multi-currency ledgers carry the original amount and currency beside the base amount, and the exchange rate used is the rate on the posting date, not the rate on the day of the export. Tax lines are separate entries linked to their parent entry through parentEntryId, so a sales invoice with tax is three or more rows rather than one. Attachments are never included in an export; only their file names and sizes are listed. Exports are capped at five thousand rows per call, and when the cap is reached the response sets truncated to true and returns a nextCursor that the next call must pass back unchanged. Rate limits allow sixty calls per minute per company, and a call over the limit returns an error with a retryAfterSeconds value that should be honored before retrying. Access is limited to the companies the signed-in user can read, and a company id outside that set returns a not-found error that deliberately does not reveal whether the company exists. Nothing in an export should be shared outside the conversation unless the user asks for it. If a tool reports an internal error, tell the user plainly and suggest trying again later instead of retrying in a loop. When a user asks for something this server cannot do, such as posting an entry, correcting a memo, or deleting a row, say so directly and do not try to approximate it with an export. When two companies share a name, ask the user which company id they mean before exporting anything, because the wrong company's ledger is worse than a short delay. Keep summaries short, lead with the totals, and only then list the individual entries the user asked about.",
  }
);

// Tool: export a ledger. The description below is over 2,048 characters.
server.registerTool(
  "export_ledger",
  {
    description:
      "Export the ledger entries for one company over a date range. Use this when a user asks for a ledger, a trial balance, or a transaction history for a named company and period. Returns an object with an entries array, a truncated flag, and a nextCursor when more rows remain. Each entry carries an id, a posting date, an account code, a signed amount in minor units, a memo, and any late-posting or reversed marker. The notes that follow are background on how the export behaves. Amounts are in the ledger's base currency in minor units, so 1250 in a USD ledger is twelve dollars and fifty cents. Dates are ISO 8601 calendar dates in the company's local time zone, and both ends of the range are inclusive. Account codes are strings that can carry leading zeros and must not be parsed as numbers. Entries posted after a period was closed carry a late-posting marker, and a reversed entry stays in the output with a reversed marker and a reversesEntryId on the entry that reverses it. Intercompany transfers appear once in each company's ledger with the counterparty company id in the memo, and the two sides net to zero across the group. Rounding differences under one minor unit are posted to the rounding account and are not errors. Multi-currency ledgers also carry the original amount and currency beside the base amount, converted at the rate on the posting date and not the rate on the export date. Tax lines are separate entries linked to their parent through parentEntryId, so an invoice with tax is three or more rows. Attachments are never included; only file names and sizes are listed. A call returns at most five thousand rows. When the cap is reached the response sets truncated to true and returns a nextCursor, which the next call must pass back unchanged along with the same company id and date range. The tool is limited to sixty calls per minute per company, and a call over the limit returns an error with a retryAfterSeconds value to honor before retrying. A company id the signed-in user cannot read returns a not-found error that does not reveal whether the company exists. Large exports are slow, so prefer a narrow date range and use the cursor to page through the rest rather than asking for a full year at once. The export never changes a ledger and is safe to repeat. If the call fails with an internal error, report it to the user instead of retrying in a loop. Posting, correcting and deleting entries are not supported here and are done in the accounting application itself. When two companies share a name, confirm the company id with the user before exporting. Summaries of an export should lead with the totals and then list the individual entries the user asked about, so the answer stays short even when the export is large.",
    inputSchema: {
      companyId: z
        .string()
        .describe("Company identifier as shown in the ledger picker, for example 'co_4821'."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ companyId }) => {
    const entries = await ledger.export(companyId);
    return { content: [{ type: "text", text: JSON.stringify(entries) }] };
  }
);
```
