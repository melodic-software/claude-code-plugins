---
description: "A plain implementation question on a topic the grounding description names (JWT validation in ASP.NET Core minimal APIs), with no mention of Dometrain and no slash command, routes to dometrain:grounding. No Dometrain tool exists in an eval run, so per SKILL.md Purpose ('When no such tool is present, say so and point to /dometrain:setup') the reply says the Dometrain tools are not available, points to /dometrain:setup, and cites no lesson deep link it could not have fetched. Read-only tools only; no grant needed."
tags: [dometrain, grounding, outcome, routing, tools-absent]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the dometrain:grounding skill. The reply says the Dometrain tools or server are not available in this session, points to /dometrain:setup (or names the Dometrain setup skill in prose), and contains no dometrain.com lesson link (no dometrain.com/take/ path and no dometrain.com URL with a ?t= timestamp)."
---

I'm adding JWT bearer token validation to an ASP.NET Core minimal API on .NET 9. Before I write it: how should I validate issuer, audience and the signing key, and where should that configuration live?
