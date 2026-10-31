---
description: "A branch adds a duration parser, an export endpoint, a container registration and a type-only module. The plan classifies each by test type, puts property tests on the parser and says what it will not test. Hard: a default plan lists example unit tests everywhere and skips the not-testing rationale."
tags: [testing, plan, outcome, hard, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "A test plan that reads the changed files, puts property tests (round trip or invariants) beside examples on parse_duration, integration tests on the export endpoint and the container registration, and lists src/models/types.py under not testing with a reason. It writes no test."
---
/testing:plan this branch, compared with main, changes:

```text
 src/api/routes.py       |  8 ++++++++   (new GET /reports/<id>/export)
 src/config/container.py |  4 ++++     (registers ReportExporter)
 src/duration.py         | 11 +++++++++++  (new parse_duration: "1h30m" -> 5400)
 src/exporter.py         | 12 ++++++++++++  (new ReportExporter.to_csv)
 src/models/types.py     | 12 ++++++++++++  (TypedDicts only)
```

The only tests today are in tests/test_routes.py and cover the old routes. What needs testing before I open the PR? Don't write any tests yet.
