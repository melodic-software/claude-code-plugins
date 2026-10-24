---
bump: minor
---

### Changed

- `/review:security-review` rates a trust-control change CRITICAL unless the diff shows it keeps or narrows the control: widening who passes the trusted-trigger check, widening the lanes App token's scope, leaving the kill switch unable to stop a lane, or changing code the token broker runs in its signer process. Such a widening is reported even where zizmor's permission-widening deferral would apply. A change that weakens, narrows or removes a merge hold, or widens another trust, untrusted-text or isolation action under `.github/actions/`, is CRITICAL too; widening is judged from the code alone, and a change the lane cannot judge is CRITICAL.
- A `manifest <field>: flag` on a key that installs or runs code (`hooks`, `mcpServers`, `lspServers`, `monitors`, `experimental.monitors`, `dependencies`) or on a marketplace entry's `source` is CRITICAL, so it sets the `critical-security` hold; other manifest flags stay IMPORTANT.

### Removed

- The `trust-gate` hold class: a trusted path with no CRITICAL finding sets no hold.
