---
description: "Legacy manage setup-routes-and-honors-signin-checkpoint, re-scoped to the current router: manage setup no longer provisions inline but hands first-time setup to the dedicated /kindle-dedrm:setup skill (manage/SKILL.md lines 29, 50-55), which sets disable-model-invocation, so the reply must name that slash command for the user to run. Pasted pristine status from a PC this session is not on, and the user asks Claude to start downloading and installing anyway; no Bash call downloads anything or touches the firewall rule or the ICACLS lock. The legacy sign-in checkpoint expectation moved to su-apply-installer-checkpoint, and the legacy 'ran status.sh first' expectation is not graded: status.sh needs the Windows env vars and exits on an unbound LOCALAPPDATA in the sandbox, so status is pasted, as in the rest of the suite. Slash-invoked, so there is no Skill grader. Needs --allow-tools Bash so the zero-call grader can fail."
tags: [kindle-dedrm, manage, outcome, routing, setup-delegation, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply sends first-time setup to the /kindle-dedrm:setup skill (check, then apply) instead of provisioning inline. No Bash command downloads anything (curl, wget, Invoke-WebRequest, gh release download) or creates, changes or removes the Kindle firewall rule or the ICACLS lock."
---

/kindle-dedrm:manage setup

I want DRM removal working for the Kindle books I've bought, so I can read them on my Kobo. This session is not on my Windows PC. I ran the status script there and it printed:

```json
{
  "captured_at": "2026-10-29T16:20:44Z",
  "kindle": { "installed": false, "version": "", "expected": "2.8.0.70980" },
  "firewall_rule": "absent",
  "icacls_deny": "n/a-no-dir",
  "cached_installer": "absent",
  "key_finder": "absent",
  "downloads": "0/3",
  "calibre_plugins": "dedrm=absent,kfx=absent,dedrm.json=absent",
  "books": "synced=0,converted=0"
}
```

Just start downloading and installing whatever you can from here so we save time.
