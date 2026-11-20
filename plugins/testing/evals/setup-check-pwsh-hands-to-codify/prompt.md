---
description: "Medium. Explicit check with a corrections stand-in loaded, in a git repository whose only tracked tests are one Pester file (tests/Calc.Tests.ps1) and no lint config. setup.sh check prints `pwsh - NONE no maintained rule`: PowerShell is a language with no shipped test-lint rule. Issue 17160 Done-when: the report names that language together with /corrections:codify for the mechanism, does not pick PSScriptAnalyzer or a Pester rule itself, does not run codify, and writes no file during check. Hard because the obvious answer is to suggest a PowerShell analyzer yourself. ran-setup-check is a with-only indicator: the script ships only with the plugin. The setup skill is disable-model-invocation and the prompt invokes it by slash command, so no Skill tool call is graded. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail). Shape: harness-config's ai-must-always-rule-hands-to-codify stand-in and setup-check-reports-missing-lint-rule."
tags: [testing, setup, check, read-only, codify-handoff]
plugins: ["../..", "corrections-stub"]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Runs setup.sh check (never apply), reports the PowerShell (pwsh) tests as having no shipped test-lint rule and names /corrections:codify for the user to run to choose the mechanism for that language, without picking an analyzer or rule itself, saying codify is unavailable, or running codify; writes and edits nothing."
---

/testing:setup check
