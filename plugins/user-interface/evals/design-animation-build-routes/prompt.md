---
schema_version: "1.1"
name: design-animation-build-routes
description: "Building an interface animation is the animation-authoring concern; with nothing ranked above it installed, design routes to /user-interface:write-animation and says so."
tags: [design, routing, animation]
runs: 3
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply routes the entrance animation to /user-interface:write-animation (the animation-authoring concern) and says which route it took"
---

Our design is settled. Now add an entrance animation to the onboarding cards.
