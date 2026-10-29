Command: python3 -m bfk.cli migrate
Input: data/accounts.jsonl with line 3 replaced by the malformed record `{"id": 99, "name": "Broken Record", "email": ` (the original lines follow it)
Exit code: 1

--- stdout ---


--- stderr ---
bfk migrate: data/accounts.jsonl:3: Expecting value (the record is cut off after "email":)
fix: complete the JSON object on line 3 or delete that line, then run the command again
