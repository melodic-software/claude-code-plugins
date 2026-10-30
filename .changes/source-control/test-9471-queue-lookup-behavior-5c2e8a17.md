---
bump: none
---

Test only: `test_verify_rules_sync.py` runs ci-status's merge-queue pass lookup from `pr-require-checks.yml` against stubbed run reads. It compares the lookup's allow and refuse answers with the gate's, where it used to check the workflow's source text. No skill, script or reference a user loads changes.
