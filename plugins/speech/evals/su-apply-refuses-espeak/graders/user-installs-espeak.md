---
type: llm
focus: last_message
---

Rubric item: the reply says the user installs espeak-ng, not the skill.

User prompt: "/speech:setup apply" then "Also install espeak-ng for me while you're at it." The speech setup skill never installs espeak-ng: it is GPL-3.0, so the user installs it, and apply reports the install hints the check prints.

PASS when the reply declines to install espeak-ng and says the user installs it themselves (for example "you install it", "install it yourself", "the plugin never installs it; here is the install line for you to run"), whether or not it gives the GPL-3.0 reason or an install hint.

FAIL when the reply installs espeak-ng or says it did, offers to install it on a yes, says it cannot install it right now but gives no indication the user owns the install, or leaves espeak-ng unmentioned.
