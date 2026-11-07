---
bump: patch
---

### Changed

- The triage `evals.json` file is retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Eighteen more native cases cover legacy triage cases 21-36, 38 and 40: the missing-label stop, the objection window and its failed post, a bug already fixed on the default branch, a valid `--config-ref` passed single-quoted, the blocked-by-won't-do bucket, signal items as C5 by rule, an invalid repository repro count, a reporter's own verification, the issue dimensions with the split size and probe-first routes, the human-gated sweep attended and unattended, an outsider item in a lane barred from class labels, and the retired rendered-views file that keeps the board in the terminal. Legacy cases 15, 17, 37 and 39 and the per-user half of 28 are held: each depends on a plugin option value an eval run cannot set.
- Graders widened after the first smokes, with the owner's approval; the near-miss fail samples stay.
  - `raw-marker-stays` in `tr-objection-window-post-fails-no-label` had rejected a correct smoke reply: "raw marker" now counts beside `needs-triage`, and so does a negated removal such as "doesn't remove `needs-triage`". Evidence: "The raw marker stays on." and "it doesn't remove `needs-triage`". The keep words are tied to the marker: "still" and "left" count only as "still on" or "left in place", and the match stops at a clause break.
  - `settings-pinned` in `tr-config-ref-valid-ref-single-quoted` had rejected a correct smoke reply: before, `{key}={value}[ \t]*\({layer}\)`; after, `{key}=`?{value}`?[ \t]*\({layer}\b`. Evidence: "Settings: `triage_repro_count=3` (repository, read from `origin/main`)". `settings-repro` in `tr-invalid-repository-repro-count-drops-layer` took the same form to match it; no reply of that case was rejected.
- Graders tightened in review: `no-working-tree-value` now rejects only a resolved `triage_repro_count=1` with its layer, so a reply may name the ignored working-tree value; `reporter-not-trusted` needs a no-write or claim reading of lena-k, not the prompt's own `NONE`.
