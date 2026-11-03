---
bump: patch
---

### Fixed

- The pr-merge lane's post-merge floor anchor now starts when every lane merge since the policy floor already carries its settled marker. The check that writes the anchor judges each settled merge the anchor needs again from its own runs, under the check's existing read caps, and passes it only when those runs show it final. The marker alone still never passes a merge, and the check's verdict and report are unchanged. Before, `anchor.json` was never written in that state.
