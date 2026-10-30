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
