# SARIF Diagnostics

Roslyn can emit structured SARIF v2.1.0 diagnostics at build time — useful for machine-readable triage of compiler/analyzer findings.

- **Cmdline syntax** — `dotnet build "/p:ErrorLog=<path>.sarif%3bversion=2.1"` (URL-escape the `;` separator between path and version; without `%3b` MSBuild truncates the property)
- **Coverage and gap** — SARIF captures compiler + analyzer + source-generator diagnostics; it does NOT capture MSBuild target errors, NuGet restore failures, or package-validation findings — those only appear in the build log
- **jq query patterns**:

```bash
# Count by severity
jq '[.runs[].results[].level] | group_by(.) | map({level: .[0], n: length})' out.sarif

# Errors only, with file/line
jq -r '.runs[].results[] | select(.level=="error") | "\(.locations[0].physicalLocation.artifactLocation.uri):\(.locations[0].physicalLocation.region.startLine) \(.ruleId) \(.message.text)"' out.sarif

# Group by ruleId
jq '[.runs[].results[].ruleId] | group_by(.) | map({rule: .[0], n: length}) | sort_by(-.n)' out.sarif
```

- **AI consumption pattern** — build output is the primary signal; read SARIF directly only when investigating a specific finding or aggregating across many diagnostics
