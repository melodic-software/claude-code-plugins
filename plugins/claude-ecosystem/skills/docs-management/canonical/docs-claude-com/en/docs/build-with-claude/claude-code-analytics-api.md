<!-- Source: https://docs.claude.com/en/docs/build-with-claude/claude-code-analytics-api -->

# Claude Code Analytics API

Programmatically access your organization's Claude Code usage analytics and productivity metrics with the Claude Code Analytics Admin API.

<Tip>
  **The Admin API is unavailable for individual accounts.** To collaborate with teammates and add members, set up your organization in **Console → Settings → Organization**.
</Tip>

The Claude Code Analytics Admin API provides programmatic access to daily aggregated usage metrics for Claude Code users, enabling organizations to analyze developer productivity and build custom dashboards. This API bridges the gap between our basic [Analytics dashboard](https://console.anthropic.com/claude-code) and the complex OpenTelemetry integration.

This API enables you to better monitor, analyze, and optimize your Claude Code adoption:

* **Developer Productivity Analysis:** Track sessions, lines of code added/removed, commits, and pull requests created using Claude Code
* **Tool Usage Metrics:** Monitor acceptance and rejection rates for different Claude Code tools (Edit, Write, NotebookEdit)
* **Cost Analysis:** View estimated costs and token usage broken down by Claude model
* **Custom Reporting:** Export data to build executive dashboards and reports for management teams
* **Usage Justification:** Provide metrics to justify and expand Claude Code adoption internally

<Check>
  **Admin API key required**

  This API is part of the [Admin API](/en/docs/build-with-claude/administration-api). These endpoints require an Admin API key (starting with `sk-ant-admin...`) that differs from standard API keys. Only organization members with the admin role can provision Admin API keys through the [Claude Console](https://console.anthropic.com/settings/admin-keys).
</Check>

## Quick start

Get your organization's Claude Code analytics for a specific day:

```bash  theme={null}
curl "https://api.anthropic.com/v1/organizations/usage_report/claude_code?\
starting_at=2025-09-08&\
limit=20" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ADMIN_API_KEY"
```

<Tip>
  **Set a User-Agent header for integrations**

  If you're building an integration, set your User-Agent header to help us understand usage patterns:

  ```
  User-Agent: YourApp/1.0.0 (https://yourapp.com)
  ```
</Tip>

## Claude Code Analytics API

Track Claude Code usage, productivity metrics, and developer activity across your organization with the `/v1/organizations/usage_report/claude_code` endpoint.

### Key concepts

* **Daily aggregation**: Returns metrics for a single day specified by the `starting_at` parameter
* **User-level data**: Each record represents one user's activity for the specified day
* **Productivity metrics**: Track sessions, lines of code, commits, pull requests, and tool usage
* **Token and cost data**: Monitor usage and estimated costs broken down by Claude model
* **Cursor-based pagination**: Handle large datasets with stable pagination using opaque cursors
* **Data freshness**: Metrics are available with up to 1-hour delay for consistency

For complete parameter details and response schemas, see the [Claude Code Analytics API reference](/en/api/admin-api/claude-code/get-claude-code-usage-report).

### Basic examples

#### Get analytics for a specific day

```bash  theme={null}
curl "https://api.anthropic.com/v1/organizations/usage_report/claude_code?\
starting_at=2025-09-08" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ADMIN_API_KEY"
```

#### Get analytics with pagination

```bash  theme={null}