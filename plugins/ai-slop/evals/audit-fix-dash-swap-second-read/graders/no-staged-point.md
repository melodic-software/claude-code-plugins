---
type: llm
focus: { source: file, path: docs/upgrade.md }
arm: both
---
This file is the result of fixing an upgrade note whose original had five sentences of the shape "claim — elaboration": "The scheduler changed the most — it now hands...", "Retries got stricter — a failed job waits...", "Shutdown is safer — the new `--drain` flag...", "One setting was renamed — `RUNNER_POOL` is now...", and "Large payloads now fail loudly — a job payload over 1 MB...". PASS only if none of the sentences that carry those five points stages its point in two parts with a colon, an em dash, an en dash, a spaced hyphen or a parenthetical where the dash was (for example "Retries got stricter: a failed job waits..."). Stating the point once, splitting it into two sentences, or joining with a comma or "so" all PASS. A colon that introduces a list or a code example is not staging. FAIL if any of the five is still staged.
