---
bump: patch
---

### Fixed

- In the merge queue, `ci-status` reads the counted pass's `verdict.json` again after 5, 15 and 30 s
  when GitHub answers a 5xx or the request gets no response; any other failure still fails at once.
  Three 503s over 26 s failed merge-group run
  [41063238235](https://github.com/melodic-software/claude-code-plugins/actions/runs/41063238235)
  under the old 5 and 10 s waits.
- The cold-read headroom check works out a cold read's cost from the live artifact listing, its
  `total_count` and the FAILs it lists, plus that listing's own pages, in place of a fixed 1,546 sized for 77 pages and 793 FAIL
  reads. A listing that does not read holds the pull request.
- `enable-auto-merge.mjs` (verifier reads and `capped-close`) and `verify-cap.mjs` tell the verdict
  reader the limit they kill it at (240 s, 30 s for a kept-answer lookup, 120 s), so a listing that
  cannot finish in that time refuses with the pages, the budget and the caller named rather than
  ending as a bare `verify:unreadable`.
- `verify-cap.mjs` skips the address-feedback or fix-ci round, for that run only, when the
  reader's listing does not fit in its 120 s, as it does when a sibling FAIL run cannot be read:
  either may hide the FAIL cap. Any other refusal still lets the round run, now with a warning
  naming the refusal and its detail instead of none, except `verify:fail` on an address-feedback
  round sent for that FAIL, which expects it.
- `verify-cap.mjs` logs one line per read summarizing the reader's stderr, its
  `babysit-listing-miss` lines first, so a listing that missed GitHub's live count shows in the
  dispatch job's log.
