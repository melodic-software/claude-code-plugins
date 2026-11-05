---
bump: patch
---

### Changed

- The diagnose and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Five of the ten legacy cases become new cases: `diag-preflight-unattended` (the idle-timer warning before an unattended run), `diag-shell-menu-escape` (left-click to close a shell-owned menu, with no invented cause for Escape failing), `diag-browser-not-routed` (a browser task does not fire diagnose), `setup-apply-refused` and `setup-macos-unverified`. Four were already covered by `diag-lowres-zoom`, `diag-mac-empty-capture`, `diag-routes-focus-gate`, `diag-idle-handoff` and `setup-tools-absent`. Three of those cases gain graders: `diag-lowres-zoom` checks that the reply calls the target a pixel budget and says zoom re-captures, `diag-mac-empty-capture` that the screensaver is a separate setting, and `diag-routes-focus-gate` that the reply never advises allowlisting the app that stole focus. Expectations about calling or not calling `screenshot`, `request_access`, `list_granted_applications` or a browser tool are dropped. No eval run has those tools, so they pass with or without the plugin. The legacy browser case's claim about view-only permission tiers is dropped too, because the skill leaves permission tiers to the tool descriptions. Both `evals.json` files are deleted.
