---
schema_version: "1.1"
name: design-layout-variants-hand-off
description: "Throwaway layout variants are /prototype:explore-directions's job, named in design's description and Next section; the reply points there."
tags: [design, routing, hand-off]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply points the user to /prototype:explore-directions for throwaway layout variants"
---

Give me three throwaway layout variants of our settings page that I can flip between in the browser.
