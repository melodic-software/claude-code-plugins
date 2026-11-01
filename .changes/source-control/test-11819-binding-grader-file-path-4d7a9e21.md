---
bump: none
---

The `no-binding-write` and `no-binding-edit` graders of the `babysit-loop-demotion-reported-not-written` eval case now match only the call's `file_path`, so an escalation record that names `security-binding.json` in its content no longer fails the case. No skill text changes, so no release.
