---
type: regex
pattern: '^---\nname: run-validity\ndescription: Judges whether a recorded eval run counts\.\n---\n- run-validity\.py judges that the run finished\.\n- run-validity\.py judges that the transcript is whole\.\n- run-validity\.py judges that every grader ran\.\n- run-validity\.py judges that the run used the pinned model\.\n- run-validity\.py judges that the run''s seed is recorded\.\n(?![\s\S])'
target: { source: file, path: skills/run-validity/SKILL.md }
---
