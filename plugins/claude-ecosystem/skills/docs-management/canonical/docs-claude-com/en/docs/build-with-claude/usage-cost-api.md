<!-- Source: https://docs.claude.com/en/docs/build-with-claude/usage-cost-api -->

# Usage and Cost API

Programmatically access your organization's API usage and cost data with the Usage & Cost Admin API.

<Tip>
  **The Admin API is unavailable for individual accounts.** To collaborate with teammates and add members, set up your organization in **Console → Settings → Organization**.
</Tip>

The Usage & Cost Admin API provides programmatic and granular access to historical API usage and cost data for your organization. This data is similar to the information available in the [Usage](https://console.anthropic.com/usage) and [Cost](https://console.anthropic.com/cost) pages of the Claude Console.

This API enables you to better monitor, analyze, and optimize your Claude implementations:

* **Accurate Usage Tracking:** Get precise token counts and usage patterns instead of relying solely on response token counting
* **Cost Reconciliation:** Match internal records with Anthropic billing for finance and accounting teams
* **Product performance and improvement:** Monitor product performance while measuring if changes to the system have improved it, or setup alerting
* **[Rate limit](/en/api/rate-limits) and [Priority Tier](/en/api/service-tiers#get-started-with-priority-tier) optimization:** Optimize features like [prompt caching](/en/docs/build-with-claude/prompt-caching) or specific prompts to make the most of one’s allocated capacity, or purchase dedicated capacity.
* **Advanced Analysis:** Perform deeper data analysis than what's available in Console

<Check>
  **Admin API key required**

  This API is part of the [Admin API](/en/docs/build-with-claude/administration-api). These endpoints require an Admin API key (starting with `sk-ant-admin...`) that differs from standard API keys. Only organization members with the admin role can provision Admin API keys through the [Claude Console](https://console.anthropic.com/settings/admin-keys).
</Check>

## Partner solutions

Leading observability platforms offer ready-to-use integrations for monitoring your Claude API usage and cost, without writing custom code. These integrations provide dashboards, alerting, and analytics to help you manage your API usage effectively.

<CardGroup cols={3}>
  <Card title="Datadog" icon="chart-line" href="https://docs.datadoghq.com/integrations/anthropic/">
    LLM Observability with automatic tracing and monitoring
  </Card>

  <Card title="Grafana Cloud" icon="chart-area" href="https://grafana.com/docs/grafana-cloud/monitor-infrastructure/integrations/integration-reference/integration-anthropic/">
    Agentless integration for easy LLM observability with out-of-the-box dashboards and alerts
  </Card>

  <Card title="Honeycomb" icon="hexagon" href="https://docs.honeycomb.io/integrations/anthropic-usage-monitoring/">
    Advanced querying and visualization through OpenTelemetry
  </Card>
</CardGroup>

## Quick start

Get your organization's daily usage for the last 7 days:

```bash  theme={null}
curl "https://api.anthropic.com/v1/organizations/usage_report/messages?\
starting_at=2025-01-08T00:00:00Z&\
ending_at=2025-01-15T00:00:00Z&\
bucket_width=1d" \
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

## Usage API

Track token consumption across your organization with detailed breakdowns by model, workspace, and service tier with the `/v1/organizations/usage_report/messages` endpoint.

### Key concepts

* **Time buckets**: Aggregate usage data in fixed intervals (`1m`, `1h`, or `1d`)
* **Token tracking**: Measure uncached input, cached input, cache creation, and output tokens
* **Filtering & grouping**: Filter by API key, workspace, model, service tier, or context window, and group results by these dimensions
* **Server tool usage**: Track usage of server-side tools like web search

For complete parameter details and response schemas, see the [Usage API reference](/en/api/admin-api/usage-cost/get-messages-usage-report).

### Basic examples

#### Daily usage by model

```bash  theme={null}
curl "https://api.anthropic.com/v1/organizations/usage_report/messages?\
starting_at=2025-01-01T00:00:00Z&\
ending_at=2025-01-08T00:00:00Z&\
group_by[]=model&\
bucket_width=1d" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ADMIN_API_KEY"
```

#### Hourly usage with filtering

```bash  theme={null}
curl "https://api.anthropic.com/v1/organizations/usage_report/messages?\
starting_at=2025-01-15T00:00:00Z&\
ending_at=2025-01-15T23:59:59Z&\
models[]=claude-sonnet-4-5-20250929&\
service_tiers[]=batch&\
context_window[]=0-200k&\
bucket_width=1h" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ADMIN_API_KEY"
```

#### Filter usage by API keys and workspaces

```bash  theme={null}
curl "https://api.anthropic.com/v1/organizations/usage_report/messages?\
starting_at=2025-01-01T00:00:00Z&\
ending_at=2025-01-08T00:00:00Z&\
api_key_ids[]=apikey_01Rj2N8SVvo6BePZj99NhmiT&\
api_key_ids[]=apikey_01ABC123DEF456GHI789JKL&\
workspace_ids[]=wrkspc_01JwQvzr7rXLA5AGx3HKfFUJ&\
workspace_ids[]=wrkspc_01XYZ789ABC123DEF456MNO&\
bucket_width=1d" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ADMIN_API_KEY"
```

<Tip>
  To retrieve your organization's API key IDs, use the [List API Keys](/en/api/admin-api/apikeys/list-api-keys) endpoint.

  To retrieve your organization's workspace IDs, use the [List Workspaces](/en/api/admin-api/workspaces/list-workspaces) endpoint, or find your organization's workspace IDs in the Anthropic Console.
</Tip>

### Time granularity limits

| Granularity | Default Limit | Maximum Limit | Use Case               |
| ----------- | ------------- | ------------- | ---------------------- |
| `1m`        | 60 buckets    | 1440 buckets  | Real-time monitoring   |
| `1h`        | 24 buckets    | 168 buckets   | Daily patterns         |
| `1d`        | 7 buckets     | 31 buckets    | Weekly/monthly reports |

## Cost API

Retrieve service-level cost breakdowns in USD with the `/v1/organizations/cost_report` endpoint.

### Key concepts

* **Currency**: All costs in USD, reported as decimal strings in lowest units (cents)
* **Cost types**: Track token usage, web search, and code execution costs
* **Grouping**: Group costs by workspace or description for detailed breakdowns
* **Time buckets**: Daily granularity only (`1d`)

For complete parameter details and response schemas, see the [Cost API reference](/en/api/admin-api/usage-cost/get-cost-report).

<Warning>
  Priority Tier costs use a different billing model and are not included in the cost endpoint. Track Priority Tier usage through the usage endpoint instead.
</Warning>

### Basic example

```bash  theme={null}
curl "https://api.anthropic.com/v1/organizations/cost_report?\
starting_at=2025-01-01T00:00:00Z&\
ending_at=2025-01-31T00:00:00Z&\
group_by[]=workspace_id&\
group_by[]=description" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ADMIN_API_KEY"
```

## Pagination

Both endpoints support pagination for large datasets:

1. Make your initial request
2. If `has_more` is `true`, use the `next_page` value in your next request
3. Continue until `has_more` is `false`

```bash  theme={null}