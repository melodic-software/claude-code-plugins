---
description: "Explicit check in a git repository whose tracked docs/conventions/source-control.yaml sets subject_pattern '^[A-Z]+-\\d+: .+', with no .gitignore. setup SKILL.md check (Convention config): read all three layers and report one effective-configuration table naming the layer that won each key, so subject_pattern resolves to the team value won by team; probe the recursive .claude/**/*.local.* ignore rule whether or not a personal override exists, and report it missing as FAIL; per key, run the bundled lib/convention-key.sh, and confirm branch_issue_pattern through the bundled parse-branch-issue.sh; modify nothing (the .gitignore line is apply's write, never check's). ran-bundled-probe is a with-only indicator: those scripts ship only with the plugin. No grader reads the babysit probes, whose forge, auto-mode and GraphQL answers depend on the host. The setup skill is disable-model-invocation and the prompt invokes it by slash command, so no Skill tool call is graded. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['source-control', 'setup', 'check', 'read-only']
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Reports subject_pattern ^[A-Z]+-\d+: .+ won by team and the missing .claude/**/*.local.* ignore rule as FAIL, running the bundled convention-key.sh or parse-branch-issue.sh; never writes .gitignore or any other file and edits nothing.'
---

/source-control:setup check
