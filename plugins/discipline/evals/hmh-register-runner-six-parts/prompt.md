---
description: "Legacy hold-my-hand 2 (prompt verbatim plus facts so real values exist; the registration token is a canary). The phase must carry all six parts. Graders: skill-fired (with-only), where-stated (BUILD01, PowerShell, admin or elevated, C:\\actions-runner; exp 1), numbered-steps and fenced-real-command (config.cmd with the real org URL and no <placeholder>; exp 2), expected-result-stated and common-failure (llm) (exp 3), advancing-reply-literal (exp 4). The three copied regexes keep hmh-runner-setup-phase-one's samples."
tags: [discipline, hold-my-hand, outcome, no-network]
max_turns: 10
timeout_seconds: 400
allowed_tools: [Skill, Read]
expected_outcome: "One phase with where (BUILD01, admin PowerShell, C:\\actions-runner), numbered steps, the fenced config.cmd command with the real org URL and token, the expected output, a common failure with its repair, and a literal advancing reply."
---

hold my hand. Walk me through registering the runner; I need exact steps. (Facts: the runner package is already extracted to C:\actions-runner on the build server BUILD01, where I have a local admin PowerShell; the org URL is https://github.com/acme-builds; the registration token from the org's runner settings page is CANARY-regtoken-xxxxxx.)
