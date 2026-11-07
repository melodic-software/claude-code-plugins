---
description: 'Legacy check 1. With one zero-match, one bad-bracket and one over-budget glob, check reports each rule file and pattern with its own remedy, says these failures are silent in Claude Code, and fails the gate. api-zero-match-cause and ui-bracket-fix read the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [check, glob-gate, zero-match]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply reports each failing pattern with its rule file, pattern, status and fix: api.md src/api/**/*.ts is zero-match, a rule that never fires with no warning from Claude Code, because the pattern is wrong or the code it described moved or was deleted (correct it or retire the rule); ui.md has a bad bracket to escape as \[ or close; i18n.md is over-budget, to split or replace its brace groups. The three statuses get different remedies, the reply states these failures are silent in Claude Code, and the gate fails with a non-zero exit.'
---

/instruction-placement:check

`glob-tools.sh rules` prints:

```text
PATTERN  .claude/rules/api.md  src/api/**/*.ts  1  0  zero-match
PATTERN  .claude/rules/i18n.md  locales/{en,de,fr,es,it,pt,nl,sv,pl,cs,ja}/{a,b,c,d,e,f,g,h,i,j}/{1,2,3,4,5,6,7,8,9,0}/*.json  0  0  over-budget
PATTERN  .claude/rules/sql.md  db/**/*.sql  1  37  ok
PATTERN  .claude/rules/ui.md  src/ui/[widgets/**/*.tsx  0  0  bad-bracket
SUMMARY  412  4  3  0  FAIL
```

The repository's API code lives under `packages/api/`. `render-index.sh check --file AGENTS.md` exits 0.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
