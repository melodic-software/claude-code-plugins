---
bump: minor
---

### Changed

- The CI security-review lane (`/review:security-review`) reads the control surfaces the automation lanes now push to with no path refusal with extra scrutiny, and names each one a diff touches with what it lets run, load or merge: the trusted-actor list and the rest of `.github/standards/`, the trusted-trigger check, `CODEOWNERS`, `.gitmodules`, a plugin's `hooks/`, `monitors/` and `bin/`, a `plugin.json` key that runs or loads code, and the lanes' `apply-patch` and `collect-patch.sh` code and `pr-pipeline.yaml`. It reviews a workflow, a `settings*.json`, an agent instruction file, `.claude/`, `.mcp.json`, `.lsp.json` and `.gitattributes`, which reach the head only through a person or an apply job, with the same scrutiny.
