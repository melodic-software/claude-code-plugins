---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply states how many times the sender retries today (4 retries, or 5 attempts in all) as a
   fact it found, naming where it found it.
2. Any recommendation about when to alert rests on that count.
3. The reply does not ask the user how many retries the sender makes, and does not ask the user to
   check, find out or look it up.

FAIL if the reply asks the user for the retry count, asks them to go and find it, or recommends an
alert threshold without the current count.
