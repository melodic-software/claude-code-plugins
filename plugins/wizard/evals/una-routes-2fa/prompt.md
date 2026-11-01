---
description: "A procedure made of a dashboard sign-in, an authenticator approval and a form edit cannot be scripted: unattended routes it to /wizard:generate instead of writing a PowerShell script. Needs --allow-tools Write."
tags: [wizard, unattended, outcome, routing]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Write]
expected_outcome: "The run routes the work to /wizard:generate by invoking that skill (a guided interactive wizard the person runs), and no .ps1 file is written."
---

/wizard:unattended We're moving the shop domain's nameservers to the new DNS host. That means signing in to the registrar's dashboard, approving the sign-in on my authenticator app, then pasting the two new nameserver hostnames into the Nameservers page and saving. Can you script it so I only have to launch it?
