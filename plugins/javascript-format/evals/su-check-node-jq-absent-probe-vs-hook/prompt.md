---
description: "check, then asked how a missing node and a missing jq are graded and how the SessionStart probe's biome lookup differs from the hook's. setup SKILL.md step 7 (run command -v node via Bash; a missing node is FAIL, a hook launch error, not a skip notice, since every hook launch goes through node hooks/exec-bash.mjs), step 2 (a missing jq is FAIL and the batch hook then does nothing) and step 3's last paragraph (read when and local_bin in prerequisites.json and findLocalBin in lib/prerequisites.mjs and compare them with the adapter's walk). hooks/javascript-format.sh exits silently without jq and the SessionStart probe reports jq, which prerequisites.json declares; the README says the batch row prints nothing, so there is no skip notice to point at. No fixture can take node or jq off the eval host's PATH, so the prompt supposes the state and the graders allow a reply that notes this session differs. The scaffold has a root biome.json, so the probe's when condition holds. node-probe-ran stays in both arms; reads-probe-manifest and reads-probe-code are with-only, since both files ship only with the plugin. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, check, read-only, narration, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "command -v node runs and prerequisites.json and lib/prerequisites.mjs are read; no install, biome check or format run, install.mjs write verb, Write or Edit; the reply grades a missing node FAIL (a hook launch error, not a skip notice, because every hook launch goes through node hooks/exec-bash.mjs) and a missing jq FAIL (the batch row does nothing), says the SessionStart probe resolves biome separately from the hook's walk, and says a PASS on the Biome row means the hook resolves it."
---

/javascript-format:setup check

Run check as usual, its Node probe included. Then suppose node and jq were not on PATH in this shell, with biome still under node_modules/.bin at the repo root. How would check grade each of the two, and what would the hooks do without it? Does the SessionStart probe find biome the same way the hook does, and what does a PASS on the Biome row tell me?
