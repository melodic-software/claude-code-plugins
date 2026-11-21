---
bump: patch
---

### Fixed

- The `simple-system-prompt` lever now describes `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=0`, which gives every model the full system prompt, beside `=1`. Its lean-prompt probe record now says that from Claude Code 2.1.330 an unrecognized model name gets the shorter prompt, including a name containing sonnet or haiku.
