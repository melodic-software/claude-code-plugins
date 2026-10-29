---
bump: minor
---

### Added

- central lane grant file, and a refusal that keeps lane patches off it and the trusted-actor list

  `.github/actions/resolve-config/lane-grants.json` holds one row per repository the lanes token broker admits, keyed by repository id ([ADR 0085](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md) Decision 2): the lanes and activities it may run with each activity's effect, its trusted-actor additions and the ci-workflows commits whose reusables may mint. The rows for claude-code-plugins and pr-pipeline-sandbox reproduce what each repository's own configuration grants today. Nothing reads the file yet; the broker reads it after its one-time change (Decision 7). Every `patch-rules.json` row must now refuse the new `lane-grants` class, which covers that file and `.github/standards/trusted-actors/trusted-actors.json` in any case and through any `..` segment, a rename into either included, so no lane patch can change who may start a lane or what it may mint (Decision 6). The issue lane's model is denied `Edit` on both paths. A patch-rules row without the class fails `checkPatchRules`. ([#7656](https://github.com/melodic-software/claude-code-plugins/issues/7656))
