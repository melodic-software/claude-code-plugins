---
type: regex
pattern: '^---\nname: run-review\ndescription: Judges a finished eval run against the checks run-validity\.py applies\.\n---\n# Run review\n- Read the run''s transcript and its graders before judging it\.\n- `run-validity\.py` judges whether every grader ran\.\n- `run-validity\.py` judges whether the run hit its turn limit\.\n- `run-validity\.py` also judges whether each run''s transcript names its check\.\n(?![\s\S])'
target: { source: file, path: skills/run-review/SKILL.md }
---
