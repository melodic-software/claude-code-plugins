---
description: 'Legacy attend-queue 3. Two [escalated] rows back to back: the lane restates item, decision and each option''s consequence before asking, and repeats the full restatement for the second row instead of carrying context over, writing each answer back only after it arrives. both-rows-restated reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, brief-before-ask, escalation, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Before posing the escalated question, the lane restates #418 "Uploader retries transient S3 5xx forever", the decision (which retry strategy to keep), and the consequence of each of the two options as the marker states them, then poses the question and waits. Only after the operator''s answer, (a), does it write that answer back and move on. For the next row it restates #503 "Digest CLI crashes on an empty transcript file" in full again: the decision (how an empty transcript should be handled) and what each option causes, never assuming the previous row''s context carries over. Neither restatement is dropped or abbreviated, and neither invents detail the markers do not supply. Each answer is written back only after the operator''s response.'
---

/work-items:attend-queue

The operator works two rows back to back in the same pass.

Row 1, [escalated] #418 "Uploader retries transient S3 5xx forever". The worker's escalation marker asks which retry strategy to keep: (a) capped exponential backoff, 5 attempts then dead-letter: bounded worst-case latency, but a long outage drops uploads to the dead-letter queue; (b) unbounded backoff with a 30-minute ceiling: no upload is ever dropped, but a sustained outage holds worker slots indefinitely. The operator answers: "take (a), the capped backoff."

Row 2, [escalated] #503 "Digest CLI crashes on an empty transcript file". The worker's escalation marker asks how an empty transcript should be handled: (a) exit 0 with an empty digest: scripted callers keep working, but an empty input goes unnoticed; (b) exit 2 with an error naming the file: the empty input is surfaced, but callers that pass optional transcripts start failing. The operator answers: "take (b), fail loudly."

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
