---
bump: minor
---

### Changed

- A pr-verify `fail` goes to an `address-feedback` round instead of a person. `pr-feedback-dispatch.yml` also runs when `pr-verify` completes: its new `post-verify-notes` job posts a fail verdict's summary and notes on a lanes App pull request, still at the judged head, as file-level review comments by `github-actions[bot]` whose first line is `<!-- pr-verify:fail-note -->` (`.github/scripts/pr-unblock/verify-notes.mjs`), once per head. The dispatch job then decides as for a review run, with the newest completed review run at that head as its recorded upstream, so the gate and the broker check the same run as before.
- `address-feedback` keeps such a thread as the `verifier`'s finding, beside the reviewer bot's, when its review is `github-actions[bot]`'s on a marker-confirmed head. The round cap, the scope rule and the reply job are unchanged.
- The verifier prompt passes work the spec does not ask for with a note (`pass-notes`). It fails only a spec not delivered, a correctness or safety problem, a change of intent, or a change to a hold the owner keeps, and asks each note to start with its file path so the note lands on that file.
