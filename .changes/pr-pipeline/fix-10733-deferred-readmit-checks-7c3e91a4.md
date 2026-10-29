---
bump: patch
---

### Fixed

- work-unblock's hourly sweep no longer re-admits an `admission-deferred` issue on fewer checks than intake's admission. A deferred issue that now carries `do-not-merge`, or whose `work-class: untrusted-provenance` label someone unlisted removed, stays deferred, as one with `needs-human` or the untrusted-provenance label already did. One that lost `status: ready` loses `admission-deferred`. One that gained `area: security`, or whose body was edited, after its newest `admission-deferred` add gets the admission comment and loses `status: ready` and `admission-deferred`. It parks at `status: needs-decision` for the security area, else at `status: confirmed`. Before, the sweep added `agent-ready` to any of these issues once its blockers were closed. `decide()`, which judges a person's mark on a deferred issue, refuses an issue that carries `do-not-merge` or `needs-human`, or that changed in the same ways, whatever `admission-rules.json` lists. A mark refused that way parks at `status: needs-decision`, as any refused mark does ([#10733](https://github.com/melodic-software/claude-code-plugins/issues/10733)).
