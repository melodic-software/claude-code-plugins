---
type: regex
pattern: '^---\nname: run-review\ndescription: [^\n]+\n---(?=[\s\S]*\n# Run review\n)(?=[\s\S]*\n- Read the run''s transcript and its graders before judging it\.\n)(?=[\s\S]*\n- `run-validity\.py` judges whether every grader ran\.\n)(?=[\s\S]*\n- `run-validity\.py` judges whether the run hit its turn limit\.\n)(?=[\s\S]*\n- `run-validity\.py` also judges whether each run''s transcript names its check\.\n)\n(?:[^\n]*\n){0,6}(?![\s\S])'
target: { source: file, path: skills/run-review/SKILL.md }
---
