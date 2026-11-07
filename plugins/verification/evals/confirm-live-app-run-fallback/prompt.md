---
description: 'Legacy confirm 9. Live-app run and observe is delegated: /testing:run-e2e is primary for an orchestrated app, the bundled /run supplementary, and the bundled /verify only suggested for the person to run (SKILL.md 274-283, 304-322). When /run cannot infer the launch, the run falls back to /testing:run-e2e and says so. Neither plugin nor bundled skill loads in a run, so the prompt narrates them, framed like the existing narration cases, and asks for the calls written out rather than made. falls-back-to-run-e2e and suggests-verify grade the reply; delegation-and-fallback (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, outcome, live-app, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Falls back from the bundled /run to /testing:run-e2e and says it did, never swaps in a static check, reimplements no launch, and offers /verify as something the person can run rather than calling it.'
---

/verification:confirm outcome. Run the live app and show me the change working. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. The testing plugin is installed: /testing:run-e2e resolves in this session, and so do the bundled /run and /verify skills. The project is an Aspire app; the change edits the order history page in src/web/Pages/Orders.razor. You already called the bundled /run, and it reported that it could not infer how to launch this project. Do not call any skill: write out each skill call you would make from here on, with its exact arguments, then what you tell me about how the live run went, then stop.
