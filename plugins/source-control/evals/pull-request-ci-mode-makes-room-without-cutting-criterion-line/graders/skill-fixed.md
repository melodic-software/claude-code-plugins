---
type: regex
pattern: '^(?!(?:[^\n]*\n){10}[\s\S])(?=[\s\S]*\n- run-validity\.py judges that the run finished\.(?:\n|(?![\s\S])))(?=[\s\S]*\n- run-validity\.py judges that every grader ran\.(?:\n|(?![\s\S])))(?=[\s\S]*\n- run-validity\.py judges that the run used the pinned model\.(?:\n|(?![\s\S])))(?=[\s\S]*\n- run-validity\.py judges that the run''s seed is recorded\.(?:\n|(?![\s\S])))'
target: { source: file, path: skills/run-validity/SKILL.md }
---
