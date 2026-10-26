---
bump: patch
---

### Security

- The schema refuses `scripts/run-test-file.sh` and skill-quality's `check-skill.sh`, the `verify-scripts` that run checkout code, on a skill whose effect is not `read`, since that skill runs in `pr-run-activity-write.yml`'s run job, which holds the lane token and `id-token: write`. A read skill with `applied-by.patch` still lists them; it runs in the read runner, whose run job holds neither. On such a skill, `checks` and `self-checks` may not name a script that runs the checkout's test files (`affected-tests.sh`, `run-outside-node-suites.sh`, `selection-audit.sh`, `check-guardrails-ps-differential.sh`, `run-test-file.sh`); `check-affected.sh --tests` stays allowed, since from the base copy it skips the branch's tests. The write runner no longer installs Python and pytest for the test-file runner ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#skill-activities)).
