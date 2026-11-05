---
bump: patch
---

### Changed

- name provenance: untrusted as the merge gate's trust-hold label

  `UNTRUSTED_PROVENANCE_LABEL` is now `provenance: untrusted`. The hold
  matches any label naming untrusted work, so the legacy
  `work-class: untrusted-provenance` still holds a merge; the refusal
  reason codes are unchanged.
