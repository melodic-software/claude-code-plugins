---
description: "Several-repositories improve, ready-flip half. Narration: no source-control plugin loads, so the prompt gives as facts that Steps 1 to 4.6 already ran for peer/ledger-cli and its draft pull request is open. In a several-repositories run no step asks inside a repository's run, and the request does not authorize the flip, so the run leaves the PR as a draft and says so (reports-left-draft): no gh pr ready (no-ready-command), no pull-request ready skill (no-ready-skill), no question (no-ask-tool, no-question-in-reply). Needs --scaffold and --allow-tools Bash so no-ready-command can fail."
tags: [improve, several-repositories, ready-flip, narration]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, AskUserQuestion]
expected_outcome: "The run does not mark pull request #7 ready, asks no question, and reports that the PR stays a draft because the request did not authorize the flip."
---

Run /improvement:improve --repo peer/ledger-cli src/report.js --focus standards.

Facts for this run, take them as given: `gh` is installed and authenticated for this repository's forge. Steps 1 to 4.6 already ran for peer/ledger-cli earlier in this run: the improvement is committed and pushed on `refactor/improve-report-rounding`, and draft pull request #7 for it is open. Resume that repository's run at Step 4 item 7 (Ready) and finish the run with its report.
