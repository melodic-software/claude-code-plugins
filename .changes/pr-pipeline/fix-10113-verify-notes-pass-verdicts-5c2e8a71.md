---
bump: minor
---

### Added

- The skip reason `pass-only` in `$defs/skip-reason`: the reply check of a pass-only address-feedback round, which ran no model and only resolved fail-note threads a pr-verify pass superseded. `feedback-dispatch.mjs` leaves such a check out of its release reads, so it neither releases a head nor hides the `no-model-turn` or `finding-stands` skip of the round before it. `pr-unblock.yml` takes the new `verify-pass-head` input for that round.

### Fixed

- A pr-verify `pass` or `pass-notes` verdict now clears the fail-note threads pr-verify left open on earlier heads, which kept a passing PR blocked under required thread resolution ([#10113](https://github.com/melodic-software/claude-code-plugins/issues/10113)). `pr-feedback-dispatch.yml`'s `post-verify-notes` job now downloads a pass verdict too, by `write-verdict.mjs` `NAME`'s grammar (`-i` is a fail's alone), and still fails on a verdict-shaped name no reader takes. For a pass on an open PR still at the judged head it posts and resolves nothing: it reads the review threads, and when an unresolved `<!-- pr-verify:fail-note -->` thread by `github-actions[bot]` from another head is open (`address-feedback.mjs` `staleVerifyNotes`, by the first comment's original commit), it names the head in the new `pass-head-sha` output. The dispatch job then sends `pr-unblock.yml` a pass-only round with the new `verify-pass-head` input, through the newest completed review run at that head. In that round `address-feedback-select` lists the stale threads in `run.json`'s `stale_notes`, its `proceed` output stays empty so no model job and no neutral check runs, and `publish-feedback` resolves each one still open and stale while the PR head is the passing one, as the lanes App, posting no reply and no round marker, and skips `pass-only`; a failed resolve does not stop the others, then fails the job. A pass with no such thread dispatches nothing, and the fail path's dispatch gate is unchanged. No job's permissions change.
