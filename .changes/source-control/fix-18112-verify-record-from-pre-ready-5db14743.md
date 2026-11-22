---
bump: patch
---

### Fixed

- `ready` no longer needs a person to record the verify result when the base's `pre_ready` turns `verify` off. `read-pre-ready.sh --repo <owner/repo> --base <b>` fetches the base's config and the default branch itself, so a subagent no longer has to pipe a `gh api -i` response into it, and it fails closed on every error it did before. `verify-gate.sh record --from-pre-ready --repo <owner/repo> --base <b> --head <sha>` records `skipped` only when that read finds the default branch's list disabling `verify`; any other read records nothing and exits 4. A `pass` still comes only from the gate's own exit, and a bare `--result skipped` stays for a present person's `--skip` ([#18112](https://github.com/melodic-software/claude-code-plugins/issues/18112)).
