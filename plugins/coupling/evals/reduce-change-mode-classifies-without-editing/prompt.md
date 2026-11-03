---
description: 'The scaffold repository states D:\data\ccproxy in README.md, scripts/provision.ps1 (a default), CHANGELOG.md, an approved PLAN.md and tests/fixtures/config.json; value-sites.py classifies them setup, setup, record, contract and fixture.'
tags: ['reduce']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
max_turns: 40
timeout_seconds: 900
expected_outcome: 'Runs the bundled value-sites inventory for every spelling of the old path, classifies the README and script default as setup sites with a proposed reference form, leaves the CHANGELOG as a record, proposes a correction for PLAN.md instead of editing it, flags the fixture for a person, and makes no edits because apply was not given.'
---

/coupling:reduce change 'D:\data\ccproxy' 'E:\data\ccproxy'

We moved the data volume. The old path is in the README, a provisioning script default, the CHANGELOG, an approved PLAN.md, and a test fixture.
