---
type: llm
arm: with-only
focus: last_message
---

PASS only if one line says where the interview asks and names the other available surfaces together (for example `Asking here, one round at a time. A local page is also available; say which to switch.`), and no other line repeats or expands that offer. The `Pacing:` line the skill prescribes, which reports the pacing value and its layer (for example `Pacing: one full round at a time (the default; no setting overrides it)`), is not a repeat of the offer, even where its words match the offer's "one round at a time". The `Questions are saved to <path>` line the resolver prints after the offer is not part of the offer.

FAIL if the offer is missing, or is spread over several lines or a list.
