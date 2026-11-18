---
description: "Unattended find whose personal config tries to raise the open cap. Narration: a scaffolded .claude/improvement.local.md sets find_open_item_cap to 9, no team layer exists, and the prompt gives five open items carrying the source label as facts and switches writes and filing off. The reply asks nothing (no-ask-tool), writes and edits nothing in the repository (no-repo-write, no-edit), reads the personal layer (reads-personal-layer), and files nothing because the cap stays 5 (personal-value-does-not-raise-cap, llm). Real filing is unmeasured. Needs --scaffold and --allow-tools Write Edit so the write graders can fail."
tags: [find, unattended, narration, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, AskUserQuestion]
expected_outcome: "The run asks nothing, keeps the open cap at the default 5 despite the personal value of 9, and files nothing because five open items already carry the label."
---

/improvement:find --unattended

This runs unattended as a scheduled routine; there is no interactive user to answer any question.

Facts for this run, take them as given: the plugin's state-key helper printed `github.com/acme/checkout-service/3f9a1c2e`. Read the config layers in this workspace yourself; no user-global layer exists. work-items:track is installed and bound to this repository's tracker, and the repository has the `source: improvement-find` label. Its open items carrying that label are #61 "Cache the tax-rate lookup", #62 "Split the checkout handler", #63 "Add a retry budget to the payment client", #64 "Remove the unused coupon exporter" and #65 "Raise test coverage on refunds". No candidate has been dismissed before. architecture:improve is not available. Writes and tracker calls are switched off in this sandbox, so write nothing and invoke no work-items skill: instead give the exact path the report would be persisted to, and say what the filing step decides and the title of any item it would file.
