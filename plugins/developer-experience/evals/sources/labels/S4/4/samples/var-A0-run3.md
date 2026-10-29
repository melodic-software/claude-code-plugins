Command: python3 -m bfk.cli migrate
Input: data/accounts.jsonl with line 3 replaced by the malformed record `{"id": 99, "name": "Broken Record", "email": ` (the original lines follow it)
Exit code: 1

--- stdout ---


--- stderr ---
bfk migrate: error: data/accounts.jsonl, line 3: malformed record, Expecting value at column 46.
To fix: repair that line (each line must be one complete JSON object) or remove it, then re-run `python3 -m bfk.cli migrate`.
