---
bump: minor
---

### Changed

- `babysit_postmerge.py` demotes on a red full run only for a newly failing suite in the affected
  set of the merges since the branch's last green full run (`scripts/plan-test-lanes.sh` over that
  diff, run from the green commit's own code with no token; a window that changes the selector, or
  an empty plan, has no set and demotes). A suite outside the set demotes nothing, its merges count as
  verified, and `--remediate` files a needs-human quarantine issue for it (assigned to its
  CODEOWNERS user when a rule names one) or comments the sighting on the open one. An open
  quarantine issue excuses only out-of-set failures, until `merge.quarantine-days`; a failure
  inside the set, a failed job whose suites its
  log cannot name, an uncomputable set, and the merge gate's own suites still demote. The new
  `--judge-run RUN_ID --checks-file F [--file-quarantine]` mode applies the same rule for
  post-merge-demotion-alert.yml.
