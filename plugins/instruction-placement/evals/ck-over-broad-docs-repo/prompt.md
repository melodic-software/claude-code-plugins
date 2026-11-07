---
description: 'Legacy check 3. In a documentation repository whose **/*.md rule is over-broad, check says over-broad is advisory and never fails the gate, accepts the repository context, and names --breadth-max as the lever. names-breadth-max reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [check, over-broad, breadth-max]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply confirms over-broad is a warning, not a failure: breadth judges whether a demotion was worth making, not whether the rule is broken. It accepts that in a documentation repository a glob covering most files may be right, does not propose narrowing a glob that accurately describes its scope, names raising --breadth-max as the lever rather than living with a standing warning, and confirms the exit code is unaffected (the gate passes).'
---

/instruction-placement:check: it says one of our rules is over-broad but it's a docs repo, **/*.md really is most of it.

`glob-tools.sh rules` prints:

```text
PATTERN  .claude/rules/prose.md  **/*.md  1  880  over-broad
PATTERN  .claude/rules/site.md  site/**/*.ts  1  64  valid
SUMMARY  1000  2  0  1  PASS
```

The repository is a documentation site: 880 of its 1,000 tracked files are Markdown pages, and `.claude/rules/prose.md` holds the house style for every page.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
