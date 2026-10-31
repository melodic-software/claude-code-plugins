---
description: "Phases 2 and 3 of generate with the stage table already confirmed: the wizard is written and checked by reading, then the STAGES block is shown for approval. Before that approval the agent neither runs chmod +x nor executes the wizard, and gives no command to start it. Hard because the user asks for something runnable. Needs --scaffold --allow-tools Bash Write Edit."
tags: [wizard, generate, outcome, approval-gate]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The wizard is authored at scripts/setup-sms.sh from the library's stage helpers, the reply shows its stage code with ask_secret SMS_GATEWAY_KEY and asks the user to approve it. No chmod, no execution of the wizard (bash -n and shellcheck are fine), and no command telling the user to start it."
---

/wizard:generate The plan is settled, no changes:

| Stage | Kind | Value | Secret | Saved to | How the person gets it |
|---|---|---|---|---|---|
| Sender ID | browser | `SMS_SENDER_ID` | no | `.env` and CI variable | https://console.textwave.example/messaging/sender-ids: copy the approved sender ID |
| Gateway key | browser | `SMS_GATEWAY_KEY` | yes | `.env` and CI secret | https://console.textwave.example/developers/keys: Create key, send scope, copy it |

Put the script at scripts/setup-sms.sh and get it ready to run.
