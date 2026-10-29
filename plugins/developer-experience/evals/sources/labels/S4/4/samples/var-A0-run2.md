Command: python3 -m bfk.cli migrate
Input: data/accounts.jsonl with line 3 replaced by the malformed record `{"id": 99, "name": "Broken Record", "email": ` (the original lines follow it)
Exit code: 2

--- stdout ---


--- stderr ---
bfk migrate: cannot read data/accounts.jsonl: line 3 is not valid JSON (the record looks truncated after "email":).
Fix: complete or remove line 3 of data/accounts.jsonl, then run the migration again. The file was left untouched.
