---
description: "Phase 1 of generate on a repository that gives no signal for where a secret lands (no workflow, no env template, no .env, no config): the reply shows the stage table and asks the user where the API key should be kept, offering .env and a CI secret, before any script exists. Hard because the user asks for the script outright. Needs --scaffold --allow-tools Bash Write Edit."
tags: [wizard, generate, outcome, stage-plan, secret-destination, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply shows a stage table with a row for the map provider's API key and asks the user where that key should be kept, naming .env and a CI or GitHub secret as the choices. No script is written, copied or edited."
---

/wizard:generate I'm trying out Mapverse for the store finder. Someone has to sign up and make an API key in their console. Can you write the setup script for that?
