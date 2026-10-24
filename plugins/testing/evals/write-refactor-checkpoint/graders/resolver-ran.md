---
type: tool_used
tool: Bash
input_match: 'resolve-config\.sh\\?"?\s+write\b'
---

Passes when a Bash call ran `resolve-config.sh write`, the skill's settings step, with `write` as
the script's first argument: the resolver reads its mode only from that position.
