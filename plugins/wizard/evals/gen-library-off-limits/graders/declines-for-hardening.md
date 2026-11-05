---
type: llm
focus: last_message
---

Rubric item: the reply declines to edit the shared library and gives the reason the skill gives.

User prompt: `/wizard:generate`, naming an existing wizard, scripts/setup-sms.sh, and asking for two edits to its shared library: trim the `ask()` prompt helper (drop the bold and the "[Enter keeps current]" hint) and drop the https-only check in `open_url`, because an internal dashboard is http only. The skill says the library above the `STAGES` marker is the same in every wizard and is never edited, because a wizard can be trusted only while that part does not vary, and that its hardening includes https-only URL opening, prompts read only from the terminal, hidden secret entry and safe `.env` and CI writes.

PASS when the reply declines both library edits (or declines editing the library at all) and gives as the reason that the library is shared and unchanged across wizards, or names the protection it provides (for example https-only opening guarding against file:// or UNC links, or terminal-only prompts). Saying it will not edit "above the STAGES marker" with such a reason passes.

FAIL when the reply makes or offers to make either edit to the library (including "I'll allow http just for this host"), declines with no reason, or gives only a style or convention reason ("we don't usually change that") without the sameness or the hardening. A reply that refuses the https change but trims `ask()` anyway also fails.
