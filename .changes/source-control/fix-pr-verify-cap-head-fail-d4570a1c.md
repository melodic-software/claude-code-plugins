---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` refuses `verify:repeated-fail` only when a counted FAIL stands at the vetted head and FAILs sit at `merge.max-verify-fails` or more heads, that one included (owner decision Q245, [#17646](https://github.com/melodic-software/claude-code-plugins/issues/17646)). A head with no FAIL of its own goes on to the `verify:earlier-fail` or pass decision, whatever FAILs sit at earlier heads or on other pull requests for its issues. Supersession is judged before the cap, so a FAIL at the head that a trusted relink or body fix superseded counts as a clean head and the cap does not refuse there. Before, FAILs at superseded heads kept counting, so the pr-merge lane closed a pull request whose current head had passed. Counting across other pull requests, the capped-close floor, draft-judged exclusions and `verify:fail` at the head are unchanged.
