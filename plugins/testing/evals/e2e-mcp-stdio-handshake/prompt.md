---
description: "A Node MCP server whose unit tests pass but whose tools never appear in the client. The non-UI route gives the stdio initialize handshake as the live test and the response fields to expect. Hard: the default answer is to rerun the unit tests or check client config."
tags: [testing, run-e2e, non-ui, outcome, hard, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Reads the server, then gives a stdio smoke test: spawn the built server, send one JSON-RPC initialize request on stdin, read one line from stdout and check protocolVersion, serverInfo.name and capabilities. It starts and installs nothing."
---
/testing:run-e2e non-ui my ticket MCP server's unit tests pass, but when I add it to my client it never shows any tools. Don't start or install anything; I'll run what you give me. What is the live test, and what should I expect to see?
