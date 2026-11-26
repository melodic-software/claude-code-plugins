---
description: "No-trigger near-miss control for engineering-concepts:adopt. The request wants a topic's concepts in view for this session only and says nothing should be saved, which the descriptions hand to engineering-concepts:load, so adopt must not load. A model without the plugin passes too; the case guards against an adopt description that fires on any request to use a topic."
tags: [engineering-concepts, adopt, load, skip, regression-guard]
max_turns: 6
timeout_seconds: 180
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "No Skill call loads engineering-concepts:adopt."
---

For this design session only, bring the engineering-concepts modularity topic into view while we sketch the export service. Don't save anything as a standard.
