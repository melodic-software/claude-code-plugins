---
description: "Known limitations (SKILL.md lines 124-128: read context/consumer-notes.md before relying on a generated playground beyond personal exploration). The user plans to feed customer-submitted query text into a data explorer, so the run reads the notes and relays the caution of consumer-notes.md lines 17-22: the template writes highlighted query text to innerHTML without escaping, so escape it first. The Read indicator is with-only, since the baseline has no spoke to read."
tags: [playgrounds, use, outcome, consumer-notes]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run reads context/consumer-notes.md, and the reply names the innerHTML rendering and says to escape or sanitize the input."
---

/playgrounds:use a data explorer for our support search queries

Once it exists I plan to paste in the raw query strings our customers type into the help center and share the page with the support team. Before I install anything: is there a known risk with that?
