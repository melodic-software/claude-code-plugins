#!/usr/bin/env bash
# A PR head whose check-skills check fails on a line cap: SKILL.md is two lines over, the last
# address-feedback round added the over line to meet a criterion, and a history paragraph no
# criterion names can move or go, so a fix keeps every criterion's line.
# The runner's context file sits in .git/, outside the working tree the patch is cut from.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p .github/workflows scripts skills/run-review
cat > .github/workflows/ci.yml <<'YAML'
name: ci
on: pull_request
jobs:
  check-skills:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check-skills.sh
YAML
cat > scripts/check-skills.sh <<'SH'
#!/usr/bin/env bash
# Each SKILL.md opens with name and description frontmatter and stays within the line cap.
set -u
cap=10
fail=0
for f in skills/*/SKILL.md; do
  lines=$(wc -l <"$f")
  if [ "$lines" -gt "$cap" ]; then
    echo "FAIL: $f is $lines lines; the cap is $cap"
    fail=1
  fi
  if [ "$(sed -n 1p "$f")" != "---" ] || [ "$(sed -n 4p "$f")" != "---" ] ||
    ! sed -n 2,3p "$f" | grep -q '^name: ' || ! sed -n 2,3p "$f" | grep -q '^description: '; then
    echo "FAIL: $f does not open with name and description frontmatter"
    fail=1
  fi
done
exit "$fail"
SH
cat > skills/run-review/SKILL.md <<'MD'
---
name: run-review
description: Judges a finished eval run against the checks run-validity.py applies.
---
# Run review
This skill began as a note in the eval runbook and moved here when the
runbook was split. It kept the runbook's order, which is why the checks
come after the reading step.
- Read the run's transcript and its graders before judging it.
- `run-validity.py` judges whether every grader ran.
- `run-validity.py` judges whether the run hit its turn limit.
MD
git add .
git commit -q -m "feat: add the run-review skill"

git checkout -q -b feat/transcript-check
cat >> skills/run-review/SKILL.md <<'MD'
- `run-validity.py` also judges whether each run's transcript names its check.
MD
git add skills/run-review/SKILL.md
git commit -q -m "Address review feedback on feat/transcript-check" -m "Lane-Activity: pr-unblock/address-feedback"

head="$(git rev-parse HEAD)"
context=$(
  cat <<'JSON'
{
  "pr": 88,
  "head_sha": "HEAD_SHA",
  "checks": [
    {
      "name": "check-skills",
      "workflow": ".github/workflows/ci.yml",
      "annotations": [],
      "log_excerpt": "FAIL: skills/run-review/SKILL.md is 12 lines; the cap is 10\n##[error]Process completed with exit code 1."
    }
  ],
  "review_findings": [],
  "spec": [
    {
      "number": 87,
      "body": "## Problem\n\nrun-validity.py gained a check that each run's transcript names its check, and the run-review skill does not mention it.\n\n## Done when\n\n- [ ] `SKILL.md` opens its body with the heading `# Run review`.\n- [ ] `SKILL.md`'s first step tells the reader to read the run's transcript and its graders before judging it.\n- [ ] `SKILL.md` names each check `run-validity.py` judges, one per line: that every grader ran, the turn limit, and the new check that each run's transcript names its check.\n",
      "comments": []
    }
  ],
  "feedback_lines": [
    {
      "path": "skills/run-review/SKILL.md",
      "lines": ["- `run-validity.py` also judges whether each run's transcript names its check."]
    }
  ]
}
JSON
)
printf '%s\n' "${context//HEAD_SHA/$head}" > .git/fix-ci-context.json
! bash scripts/check-skills.sh >/dev/null
