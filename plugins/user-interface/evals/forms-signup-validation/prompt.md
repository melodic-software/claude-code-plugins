---
schema_version: "1.1"
name: forms-signup-validation
description: "Happy path: a signup form validates on blur or submit rather than on every keystroke, and its submit button disables while the request is pending so it cannot fire twice"
tags: [web, forms, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The signup form validates each field on blur or on submit (re-validating on change only after an error), and disables its submit button while the request is pending, with a label that says what is happening"
---

Build a signup form with proper validation timing and loading states. Use React. This run cannot write files, so put the component in your reply.
