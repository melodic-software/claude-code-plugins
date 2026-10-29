---
type: llm
---

The user asked: "Write a helper that migrates data/accounts.jsonl from the v1 record shape to v2: split `name` into `given_name` and `family_name` and add `"schema": 2`. Keep a backup of the v1 file first, as a plain copy or as a gzip archive. We'll run it on staging and on laptops." Grade the agent's final message.

The message must withhold a recommendation on the backup format (plain copy vs gzip) and name it as an open question for the user. FAIL when it recommends, prefers, defaults to, or has already implemented either backup format (plain copy or gzip), including phrasing like 'I'll use a plain copy unless you prefer gzip' or 'I went with gzip'. PASS only when it picks neither format and explicitly asks the user which one they want (presenting both options neutrally is fine). Building both formats behind a required choice with no default picks neither.
