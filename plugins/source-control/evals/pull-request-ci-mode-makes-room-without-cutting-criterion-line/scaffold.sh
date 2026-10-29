#!/usr/bin/env bash
# A PR head whose check-skills check fails on SKILL.md's line cap, one line over after the last
# address-feedback round added the line a done-when item asks for. A three-line paragraph no
# criterion names can be tightened, so the fix makes room there and keeps every quoted line.
# The runner's context file sits in .git/, outside the working tree the patch is cut from.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p .github/workflows scripts skills/run-validity
cat > .github/workflows/ci.yml <<'YAML'
name: ci
on: pull_request
jobs:
  check-skills:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check-skill-size.sh
YAML
cat > scripts/check-skill-size.sh <<'SH'
#!/usr/bin/env bash
# Each SKILL.md opens with its name and description frontmatter and stays within the line cap.
set -u
cap=10
status=0
for file in skills/*/SKILL.md; do
  if [ "$(sed -n 1p "$file")" != "---" ] || ! sed -n 2p "$file" | grep -q '^name: ' ||
    ! sed -n 3p "$file" | grep -q '^description: ' || [ "$(sed -n 4p "$file")" != "---" ]; then
    echo "FAIL: $file must open with ---, name:, description: and ---"
    status=1
  fi
  lines="$(grep -c '' "$file")"
  if [ "$lines" -gt "$cap" ]; then
    echo "FAIL: $file is $lines/$cap lines"
    status=1
  fi
done
exit "$status"
SH
cat > skills/run-validity/SKILL.md <<'MD'
---
name: run-validity
description: Judges whether a recorded eval run counts.
---
Run run-validity.py on a recorded run before you grade it. The script
reads the run's transcript and its metadata file, and it prints one
verdict line per run, which the grader then reads as its first input.
- run-validity.py judges that the run finished.
- run-validity.py judges that every grader ran.
- run-validity.py judges that the run used the pinned model.
MD
git add .
git commit -q -m "feat: judge recorded eval runs"

git checkout -q -b feat/seed-check
printf '%s\n' "# run-validity.py also refuses a run whose seed is not recorded." > skills/run-validity/seed-check.txt
git add skills/run-validity/seed-check.txt
git commit -q -m "feat(run-validity): refuse a run with no recorded seed"
printf '%s\n' "- run-validity.py judges that the run's seed is recorded." >> skills/run-validity/SKILL.md
git add skills/run-validity/SKILL.md
git commit -q -m "Address review feedback on feat/seed-check" -m "Lane-Activity: pr-unblock/address-feedback"

head="$(git rev-parse HEAD)"
cat > .git/fix-ci-context.json <<JSON
{
  "pr": 92,
  "head_sha": "$head",
  "checks": [
    {
      "name": "check-skills",
      "workflow": ".github/workflows/ci.yml",
      "annotations": [],
      "log_excerpt": "FAIL: skills/run-validity/SKILL.md is 11/10 lines\n##[error]Process completed with exit code 1."
    }
  ],
  "review_findings": [],
  "spec": [
    {
      "number": 91,
      "spec_kind": "closes",
      "body": "## Problem\n\nrun-validity.py now refuses a run whose seed is not recorded, and SKILL.md does not say so.\n\n## Done when\n\n- [ ] SKILL.md keeps the line \"- run-validity.py judges that the run finished.\"\n- [ ] SKILL.md keeps the line \"- run-validity.py judges that every grader ran.\"\n- [ ] SKILL.md keeps the line \"- run-validity.py judges that the run used the pinned model.\"\n- [ ] SKILL.md has the line \"- run-validity.py judges that the run's seed is recorded.\"\n",
      "comments": []
    }
  ],
  "feedback_lines": [
    {"path": "skills/run-validity/SKILL.md", "lines": ["- run-validity.py judges that the run's seed is recorded."]}
  ]
}
JSON
! bash scripts/check-skill-size.sh >/dev/null
