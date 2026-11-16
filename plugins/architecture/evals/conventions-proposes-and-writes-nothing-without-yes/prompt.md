---
description: "improve conventions lens over a scaffolded repository with five request handlers under src/Orders/Handlers registered in src/Orders/Startup.cs and no paved-path index or boundary rule: checks the recorded sources first, proposes the request-handler building block citing the handler files, routes it as a paved-path entry for /discipline:reuse-or-replace, asks which proposals to record, and with no yes writes nothing and invokes no other skill. Source: the improve skill's evals.json case conventions-proposes-and-writes-nothing-without-yes, given a scaffold. Needs --scaffold --allow-tools Bash Write and a sandbox backend."
tags: [architecture, improve, conventions, scaffold]
runs: 6
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Agent]
expected_outcome: "Checks the enforcement ladder's boundary-rule sources and the standards index before deriving, presents the request-handler building block citing the handler files as path:line instances, names its route as a paved-path entry for /discipline:reuse-or-replace, asks which proposals to record, and writes no file and invokes no other skill."
---

/architecture:improve conventions. The repository has no paved-path index and no recorded boundary rules. Under src/Orders/Handlers there are five classes, each implementing IRequestHandler<TRequest> and registered in src/Orders/Startup.cs. Show me what conventions you find; I have not decided which to keep yet.
