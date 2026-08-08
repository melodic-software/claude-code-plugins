# Fixture: Claude Code `_meta` annotations (C17-C19)

Two servers declaring `anthropic/requiresUserInteraction`. In each, one tool declares it
as the JSON boolean `true` and one declares it as a JSON string — the value Claude Code
silently ignores, so the intended consent gate never fires. C18 turns on that JSON type.

## TypeScript (`@modelcontextprotocol/sdk`)

```ts
// Consent-shaped: the permission prompt IS the point.
server.registerTool(
  "grant_repo_access",
  {
    description:
      "Grant a collaborator write access to a repository. Use this when a human has agreed " +
      "to hand over write permission. Returns the updated collaborator record.",
    inputSchema: {
      repo: z.string().describe("Full repository name, e.g. 'acme/billing-api'."),
      user: z.string().describe("The collaborator's login, e.g. 'octocat'."),
    },
    _meta: { "anthropic/requiresUserInteraction": "true" },
  },
  async ({ repo, user }) => {
    await api.addCollaborator(repo, user, { permission: "push" });
    return { content: [{ type: "text", text: "granted" }] };
  }
);

// Same shape, declared correctly.
server.registerTool(
  "revoke_repo_access",
  {
    description:
      "Revoke a collaborator's access to a repository. Use this when a human has agreed to " +
      "remove someone's permission. Returns the removed collaborator's login.",
    inputSchema: {
      repo: z.string().describe("Full repository name, e.g. 'acme/billing-api'."),
      user: z.string().describe("The collaborator's login, e.g. 'octocat'."),
    },
    _meta: { "anthropic/requiresUserInteraction": true },
  },
  async ({ repo, user }) => {
    await api.removeCollaborator(repo, user);
    return { content: [{ type: "text", text: "revoked" }] };
  }
);
```

## .NET (`ModelContextProtocol`)

`[McpMeta]` has two forms that look alike in source and differ on the wire: the `string`
**constructor** overload serializes a .NET string, while the `JsonValue` **property** holds
raw JSON source text that is parsed.

```csharp
// Consent-shaped: the string constructor overload serializes to the JSON string "true".
[McpServerTool]
[McpMeta("anthropic/requiresUserInteraction", "true")]
[Description("Approve a pending payout. Use this when a human has agreed to release the funds. Returns the payout's new status.")]
public static async Task<string> ApprovePayout(
    [Description("The payout id, e.g. 'po_1MqLiJ2eZvKYlo2C'.")] string payoutId)
    => await payouts.ApproveAsync(payoutId);

// Same shape, declared correctly via the bool overload.
[McpServerTool]
[McpMeta("anthropic/requiresUserInteraction", true)]
[Description("Cancel a pending payout. Use this when a human has agreed to stop the transfer. Returns the payout's new status.")]
public static async Task<string> CancelPayout(
    [Description("The payout id, e.g. 'po_1MqLiJ2eZvKYlo2C'.")] string payoutId)
    => await payouts.CancelAsync(payoutId);
```
