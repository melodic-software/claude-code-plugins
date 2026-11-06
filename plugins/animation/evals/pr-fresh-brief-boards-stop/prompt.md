---
description: 'Legacy produce boards-then-stop-for-approval, from an empty workspace. produce SKILL.md lines 25-26 (produce.py init on the user''s directory), 43-45 (brief.md with Packs), 56 (produce.py boards must exit 0) and 57-58 (stop, ask for approval; no shots.json, shot render or encode). Natural-language prompt, so produce-fired is a with-only indicator. ran-init and ran-boards-gate need those calls on films/harbor (ran-boards-gate is a trace regex, so it also accepts boards . after a cd into films/harbor in the same or an earlier Bash call, with no other cd or cwd reset between); brief-names-pack reads films/harbor/brief.md for a Subject and Packs: woodcut-ink (legacy: writes the production directory the user named); never-approves, no-approval-write, no-approval-edit, no-shots-write, no-shell-writes and no-shot-render are copied from pr-boards-stop-for-approval; boards-pass-before-ask (llm, trace) checks the exit-0 rule. Watch item: model sheets need a PNG and render.py may not run in an eval run, so boards can fail to pass; boards-pass-before-ask then passes a reply that reports the failures. The asks-for-approval guard is held on #8635, because boards cannot pass here. Path refit from ~/films/harbor to the workspace. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, produce, outcome, approval-gate, no-network]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'The skill runs produce.py init on films/harbor, writes brief.md naming the woodcut-ink pack, fills the boards and runs produce.py boards, then stops and asks the user to approve them. It never runs produce.py approve, never writes approval.json or shots.json, and runs no shot render.'
---

Produce a 10 second woodcut-ink film of a harbor at dusk. Put it in films/harbor.
