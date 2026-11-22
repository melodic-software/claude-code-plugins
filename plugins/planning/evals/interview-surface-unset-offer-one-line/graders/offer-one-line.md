---
type: llm
arm: with-only
focus: last_message
---

PASS only if one line says where the interview asks and names the other available surfaces together (for example `Asking here, one round at a time. A local page is also available; say which to switch.`), and no other line repeats or expands that offer. The `Pacing:` line the skill prescribes, which reports the pacing value and its layer (for example `Pacing: one full round at a time (the default; no setting overrides it)`), is not a repeat of the offer, even where its words match the offer's "one round at a time". The `Questions are saved to <path>` line the resolver prints after the offer is not part of the offer, and neither are its `Optional:` lines, each naming an installed optional planner or offering an optional plugin (for example `Optional: the domain-driven-design plugin is not installed; say yes to install it.`), or its one-line notices (for example `shared session unavailable: no tunnel tool found`). An `Optional:` or notice line that names the other surfaces or how to switch to them again is a repeat.

FAIL if the offer is missing, or is spread over several lines or a list.
