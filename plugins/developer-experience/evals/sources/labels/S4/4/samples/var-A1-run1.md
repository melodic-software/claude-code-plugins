Command: python3 -m bfk.cli migrate
Input: data/accounts.jsonl with line 3 replaced by the malformed record `{"id": 99, "name": "Broken Record", "email": ` (the original lines follow it)
Exit code: 1

--- stdout ---


--- stderr ---
bfk migrate: data/accounts.jsonl:3: invalid JSON: Expecting value
hint: correct or remove line 3 and re-run; no backup was created and the file is unchanged.
