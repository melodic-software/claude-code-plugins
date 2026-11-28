---
description: "Hard retrieval (primary-source claim): verify an authorization exception from runtime enforcement code when secondary docs misstate it"
tags: [routing, retrieval, hard]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "outcome: denied; error_code: ERR_EXPORT_SCOPE_REQUIRED; primary_source: src/authz/export_gate.py."
---

The current directory holds documentation and source files for the `gatepass` authorization library. Answer from its files.

When an API key holds only the `read:audit` scope and sends `POST /v2/exports`, is the request allowed or denied at runtime, what exact error code is returned (or `none` if allowed), and which primary source file enforces that outcome? Reply in three lines:

outcome: <allowed or denied>
error_code: <exact error code or none>
primary_source: <path from the current directory>
