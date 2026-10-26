---
bump: patch
---

### Changed

- `babysit_merge_policy.settle_shared` holds the lane room's reuse rule for a run's post-merge report (`shared_refusal`, keeping an `unverified-stale` answer nothing moved since and a `demotion-changed` one whose demotion reads the same), and `lane_room` calls it. `babysit_verify_evidence.py settle` applies that rule without reading the report again, as the agent identity in the default branch's config: exit 0 when it stands, 1 otherwise. `settle` and `lane-room` take a required `--code-sha`, the commit whose code ran the report's check: `babysit_merge_policy.check_code_unchanged` compares the babysit-prs scripts and `docs/conventions/pr-pipeline.yaml` there with this checkout's HEAD, and a change, a missing or malformed commit or a git failure refuses the report (`code-changed`), which `lane_room` reads again.
