---
description: "check in a git repository with no .gitattributes. setup SKILL.md check step 4 (two non-failure cases: not in a repo is not applicable; in a repo with no eol= rule is inert by design; the step asks for the right classification, not for the reply to name the other case, so no grader requires that), step 5 (resolve with git check-attr; absence is INFO, not FAIL) and apply's no-eol= bullet (never writes .gitattributes). The scaffold creates no .gitattributes, so no-gitattributes-created catches a write by any tool. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'check', 'read-only']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Answers no: with no eol=lf or eol=crlf rule, resolution is entirely .gitattributes-driven, so the plugin is inert by design, reported as INFO, not FAIL; writes no .gitattributes.'
---

/eol-normalizer:setup check

git is installed, we're inside a git repo, and line endings are never normalized. Is the plugin broken?
