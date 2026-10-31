---
schema_version: "1.1"
name: component-api-props
description: "Hard (the prompt proposes is-prefixed booleans and a value-only API): a shared component's props API names props like HTML, types its size as a union, and supports both controlled and uncontrolled state"
tags: [web, component-api, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The Select API takes both defaultValue (uncontrolled) and value with a change handler (controlled), uses disabled rather than isDisabled and a size prop typed as a union of fixed values rather than an isLarge boolean"
---

Design the props API for a shared Select component in our React design system. I was going to give it a `value` prop plus booleans like `isDisabled` and `isLarge` to keep it simple. Some teams track the selected value in their own state and others just want it to work on its own. This run cannot write files, so put the props type and a usage example in your reply.
