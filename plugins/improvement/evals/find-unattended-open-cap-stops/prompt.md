---
description: "Unattended find with the open cap reached. Narration: like find-unattended-files-capped, the prompt gives the state key and the tracker's state as facts and switches writes and filing off, so the case grades the declared plan. Five open items already carry the source: improvement-find label, the only config is an old-location .claude/improvement.md that sets no find_open_item_cap (default 5), and the prompt asks for up to 3 filings. The reply asks no question (no-ask-tool), writes nothing into the repository (no-repo-write), edits nothing (no-edit), names the open cap as why nothing is filed (names-open-cap), prints the dual-read warning line naming the old file, docs/conventions/improvement.yaml and /improvement:setup apply (warns-old-file), and plans no filing despite the prompt's cap of 3 (files-nothing-at-open-cap, llm). The real tracker count is unmeasured. Needs --scaffold and --allow-tools Write Edit so the write graders can fail."
tags: [find, unattended, narration, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, AskUserQuestion]
expected_outcome: "The run asks nothing, prints one warning naming the old .claude/improvement.md, docs/conventions/improvement.yaml as where to move it and /improvement:setup apply, still ranks candidates for the report, and files nothing because five open items carrying the source: improvement-find label meet the open cap of 5, which the prompt's 'file at most 3' does not raise; it says so."
---

/improvement:find --unattended

This runs unattended as a scheduled routine; there is no interactive user to answer any question. File at most 3 items this run.

Facts for this run, take them as given: the plugin's state-key helper printed `github.com/acme/checkout-service/3f9a1c2e`. Read the config layers in this workspace yourself; no user-global layer exists. work-items:track is installed and bound to this repository's tracker, and the repository has the `source: improvement-find` label. Its open items carrying that label are #61 "Cache the tax-rate lookup", #62 "Split the checkout handler", #63 "Add a retry budget to the payment client", #64 "Remove the unused coupon exporter" and #65 "Raise test coverage on refunds"; none of them has been triaged yet. No candidate has been dismissed before. Writes and tracker calls are switched off in this sandbox, so write nothing and invoke no work-items skill: instead give the exact path the report would be persisted to, and say what the filing step decides and the title of any item it would file.
