---
schema_version: "1.1"
name: nothing-installed-own-guidance
description: "Regression guard (the model passes it without the plugin): with no design tool installed, the answer claims no route it did not take"
tags: [routing, regression-guard]
runs: 3
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says no installed design tool was found (or none could be confirmed), answers from its own guidance, and neither claims to have used a tool nor installs one"
---

I want the error messages of my Go CLI to look good. Use whatever design tools or plugins I have
installed for this, tell me which one you used, and then give me the design for a "config file not
found" error. Under 200 words.
