---
description: "A branch adds a duration parser, an export endpoint, a container registration, a type-only module, a hook-payload parser fed by another process, a client of a service that verifies its consumers' contracts and a client of a public third-party API. The plan classifies each by test type, puts property tests on the parser, a fuzz target on the hook-payload parser and a consumer-driven contract test on the billing client, sends the third-party client to testing:test-value, and says what it will not test. Hard: a default plan lists example unit tests everywhere and skips the not-testing rationale."
tags: [testing, plan, outcome, hard, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "A test plan that reads the changed files, puts property tests (round trip or invariants) beside examples on parse_duration, integration tests on the export endpoint and the container registration, a fuzz target on parse_hook_payload, a consumer-driven contract test on BillingClient, canned responses from testing:test-value and no contract test for WeatherClient, and lists src/models/types.py under not testing with a reason. It writes no test."
---
/testing:plan this branch, compared with main, changes:

```text
 src/api/routes.py       |  8 ++++++++   (new GET /reports/<id>/export)
 src/billing_client.py   | 24 ++++++++++++++++++++++++  (new BillingClient for the payments team's billing-service)
 src/config/container.py |  4 ++++     (registers ReportExporter)
 src/duration.py         | 11 +++++++++++  (new parse_duration: "1h30m" -> 5400)
 src/exporter.py         | 12 ++++++++++++  (new ReportExporter.to_csv)
 src/hook_payload.py     | 20 ++++++++++++++++++++  (new parse_hook_payload: a hook runner's JSON from stdin)
 src/models/types.py     | 12 ++++++++++++  (TypedDicts only)
 src/weather_client.py   | 15 +++++++++++++++  (new WeatherClient for a public forecast API)
```

The only tests today are in tests/test_routes.py and cover the old routes. What needs testing before I open the PR? Don't write any tests yet.
