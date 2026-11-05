---
type: llm
focus: last_message
---

Rubric item: the reply does not present a cause for the Escape failure as known.

User prompt: `/computer-use:diagnose quirks`, then, on Windows 11 with Claude Desktop, a File Explorer context menu stayed open after Claude sent a synthesized Escape twice, and the user asks how to close it and why Escape is failing. The plugin's Windows quirks file records the behavior as reproducible and its mechanism as unknown. It rules out two explanations: that the menu had not finished loading, and that the keys are routed to the window that owns the menu.

PASS when the reply either gives no cause, or says the cause is unknown, unverified or not established. It may still describe the behavior: shell-owned menus ignore a synthesized Escape, and in-app menus close on it. It may name a candidate cause if it plainly marks it as a guess and not as the reason.

FAIL when the reply states a cause as fact. Examples: the menu had not finished loading, the keystroke went to the window that owns the menu, the shell menu runs at a different integrity level or under UIPI, synthesized keys skip the menu's message loop, or the menu needs focus first. A hedge that still asserts the cause ("it's most likely because the key goes to the Explorer window, so...") followed by advice that depends on it also fails.
