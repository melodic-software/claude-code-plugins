---
description: "Phase 2 Minimize: a red loop replaying a 40-field request is shrunk one element at a time, rerunning the loop after each cut and keeping only elements whose removal turns it green, before any Phase 3 hypothesis; the minimized case becomes the regression test. Read-only: the request is described, not present, and the prompt asks what to do next, as the converted no-loop and no-blind-retry cases do"
tags: [debug, converted, narration]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Plans cuts to the body fields, headers and config one element at a time with a loop run after each, keeps an element only when removing it turns the loop green and drops one whose removal leaves it red, ranks no causes for the full 40-field request, and says the minimized case is reused as the regression test"
---

/debugging:debug my loop is red: replaying one saved POST /orders request returns a 500. The request has 40 body fields, 12 headers and 8 config values set in the test environment. The 500 repeats on every run and matches what the user reported. What next?
