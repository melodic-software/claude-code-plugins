#!/usr/bin/env bash
# Offline brief inputs with every section readable, the Cost section included, so the run exits 0.
set -euo pipefail
mkdir -p brief
printf '%s\n' '{"needs-triage": 3, "status: ready": 7, "needs-owner-decision": 1, "needs-human": 0}' >brief/counts.json
printf '%s\n' '["needs-triage", "status: ready", "needs-owner-decision", "needs-human"]' >brief/labels.json
printf '%s\n' '[]' >brief/prs.json
printf '%s\n' '[{"number": 517, "title": "Choose the retention window", "url": "https://github.com/acme/widgets/issues/517", "body": "RECOMMENDED: keep run logs for fourteen days.", "comments": []}]' >brief/decisions.json
printf '%s\n' '[{"body": "<!-- harness-ops:lane-telemetry marker=lane:work-loop -->\n- lane: work-loop\n- last-cycle: 2026-07-20T07:15Z\n- flags: none"}]' >brief/telemetry.json
printf '%s\n' '[{"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": []}}}}]' >brief/merged.json
printf '%s\n' '{"usageItems": [{"date": "2026-07-01T00:00:00Z", "product": "actions", "sku": "Actions Linux", "unitType": "Minutes", "quantity": 120, "repositoryName": "widgets", "grossAmount": 1, "discountAmount": 1, "netAmount": 0}]}' >brief/billing-usage.json
printf '%s\n' '{"budgets": [{"id": "b1", "budget_type": "ProductPricing", "budget_product_sku": "actions", "budget_amount": 0, "prevent_further_usage": true}], "has_next_page": false, "total_count": 1}' >brief/billing-budgets.json
printf '%s\n' '{"admins": ["owner-example"], "partial": 0, "repos": [{"name": "widgets", "visibility": "private", "archived": false, "collaborators": ["owner-example"], "workflows": []}]}' >brief/org-scan.json
cat >brief/azure.json <<'EOF'
{
  "account": {"id": "00000000-0000-0000-0000-000000000001", "name": "sub-example", "state": "Enabled"},
  "budgets": {"value": [{"name": "budget-example", "properties": {"amount": 100.0, "category": "Cost", "timeGrain": "Monthly",
    "currentSpend": {"amount": 1.5, "unit": "USD"}, "forecastSpend": {"amount": 3.25, "unit": "USD"},
    "timePeriod": {"startDate": "2026-07-01T00:00:00Z", "endDate": "2030-01-01T00:00:00Z"}}}]},
  "scheduledActions": {"value": [{"name": "anomaly-example", "kind": "InsightAlert",
    "properties": {"status": "Enabled", "schedule": {"frequency": "Daily", "endDate": "2030-01-01T00:00:00Z"}}}]},
  "workspaces": [{"name": "log-example", "customerId": "11111111-1111-1111-1111-111111111111", "workspaceCapping": {"dailyQuotaGb": 1.0}}],
  "laUsage": {"11111111-1111-1111-1111-111111111111": [{"Day": "2026-07-10T00:00:00Z", "GB": "0.2", "TableName": "PrimaryResult"}]},
  "pricings": {"value": [{"name": "VirtualMachines", "pricingTier": "Free"}]},
  "defenderCost": {"properties": {"nextLink": null,
    "columns": [{"name": "Cost", "type": "Number"}, {"name": "ServiceName", "type": "String"}, {"name": "MeterCategory", "type": "String"}, {"name": "Currency", "type": "String"}, {"name": "UsageDate", "type": "Number"}],
    "rows": [[2.5, "Storage", "Storage", "USD", 20260719]]}},
  "activity": [],
  "secureScores": [{"name": "ascScore", "displayName": "ASC score", "current": 30.0, "max": 60, "percentage": 0.5}],
  "advisorSecurity": [],
  "advisorCost": []
}
EOF
