---
description: "fix on a doc that paraphrases a fictional vendor's retry defaults and links to a page that cannot be fetched. A paraphrase can never be fingerprint-confirmed, so nothing is fix-eligible: the file is not edited and the reply says the finding is report-only or not fix-eligible. Needs --scaffold --allow-tools Bash Write Edit."
tags: [attribution, audit, fix, outcome, fix-eligibility]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "No Write, Edit or shell write touches docs/retry-defaults.md. The reply says nothing in it is fix-eligible, or the finding is report-only, or it made no edits because no span is fingerprint-confirmed. Reporting the paragraph as a restated fact or a suspected paraphrase is fine, as is saying the source page could not be fetched and what the run did not cover."
---

/attribution:audit fix docs/retry-defaults.md
