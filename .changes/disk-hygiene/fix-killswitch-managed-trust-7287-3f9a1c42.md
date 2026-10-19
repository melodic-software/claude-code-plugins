---
bump: patch
---

### Security

- The kill switch no longer lets a user-writable managed-settings file force-enable the execution tiers. On Linux and WSL, where `/etc/claude-code` can be user-writable, a managed value that enables execution counts only from a file that is root-owned and not writable by the current user, checked per file including each `managed-settings.d` drop-in, on the same descriptor the value is read from so the file cannot be swapped between the read and the check, and never from a symlink; an untrusted enabling value is skipped and the user setting decides. A managed value that restricts (audit-only) is still honored from any file.
