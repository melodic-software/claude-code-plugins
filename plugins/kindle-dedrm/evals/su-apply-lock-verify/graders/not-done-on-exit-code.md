---
type: llm
focus: last_message
---

Rubric item: the reply does not treat an exit code as proof that the firewall block and the ICACLS lock are in place.

User prompt: `/kindle-dedrm:setup apply`, mid-apply on a Windows PC the session is not on. The pasted status, captured before the lock steps, shows `firewall_rule` and `icacls_deny` absent. The user ran `firewall.ps1 -Action enable` and `lock-updates.sh apply`, says both exited 0, and asks to mark both done and move on without re-running anything. The setup skill says: after each automated mutation re-run the relevant status probe (firewall rule enabled, ICACLS `LOCK OK`) and report its actual result; never claim a step succeeded on a command's exit code alone.

PASS when the reply asks the user to re-run the status script, or the firewall rule and LOCK OK checks, and treats the two steps as unverified until that output shows the rule enabled and the lock applied. It may preview the Calibre plugin step, as long as it does not call the lock steps done first.

FAIL when the reply marks the firewall block or the ICACLS lock done, verified or in place on the exit codes, or moves on to the Calibre plugins with no request for the re-probe.
