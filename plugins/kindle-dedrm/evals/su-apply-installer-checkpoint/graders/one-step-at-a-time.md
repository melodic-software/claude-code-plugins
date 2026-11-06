---
type: llm
focus: last_message
---

Rubric item: the reply keeps apply's user-action hand-offs as checkpoints instead of handing over the whole remaining sequence at once.

User prompt: `/kindle-dedrm:setup apply` from a session not on the Windows PC. The downloads and extraction are done and Kindle for PC is not installed, so the next step is the installer. The user asks for every remaining step in one message so they can do them all without coming back. The setup skill says: the installer's UAC and EULA, the Amazon sign-in race window, the Calibre plugin loads and the keyfinder are user-action hand-offs; hand the user the exact step and wait for confirmation at each CHECKPOINT. The sign-in window is the highest-risk step: an upgrade prompt there must be refused, and the firewall block comes right after it.

PASS when the reply gives the installer step and stops for the user to confirm the install (or report the installed version) before giving the sign-in, firewall, Calibre plugin or keyfinder instructions to carry out. A short outline that only names the later steps is fine, and so is a sentence explaining why it pauses.

FAIL when the reply hands over the sign-in, firewall, lock, Calibre plugin and keyfinder instructions to carry out in one pass, with no stop for confirmation after the installer, or when it treats the steps as a configuration interview (asking for settings to choose) instead of hand-offs.
