#!/usr/bin/env bash
# Two usage sources with the same counts: a synthetic session transcript and a running-retro ledger.
set -euo pipefail

session_id=7f3b1c2e-4d5a-4e6f-8a9b-0c1d2e3f4a5b
mkdir -p session-data .work/running-retros

cat >"session-data/$session_id.jsonl" <<EOF
{"type":"user","uuid":"00000000-0000-4000-8000-000000000001","sessionId":"$session_id","timestamp":"2026-10-31T10:00:00.000Z","message":{"role":"user","content":"Tidy the notes file, review it, and commit."}}
{"type":"assistant","uuid":"00000000-0000-4000-8000-000000000002","sessionId":"$session_id","timestamp":"2026-10-31T10:00:10.000Z","message":{"id":"msg_01","role":"assistant","model":"claude-eval","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"toolu_01","name":"Skill","input":{"skill":"docs-hygiene:compress"}}]}}
{"type":"user","uuid":"00000000-0000-4000-8000-000000000003","sessionId":"$session_id","timestamp":"2026-10-31T10:00:20.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":"Compressed notes.md."}]}}
{"type":"assistant","uuid":"00000000-0000-4000-8000-000000000004","sessionId":"$session_id","timestamp":"2026-10-31T10:00:30.000Z","message":{"id":"msg_02","role":"assistant","model":"claude-eval","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"toolu_02","name":"Skill","input":{"skill":"source-control:commit"}}]}}
{"type":"user","uuid":"00000000-0000-4000-8000-000000000005","sessionId":"$session_id","timestamp":"2026-10-31T10:00:40.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_02","content":"Committed notes.md."}]}}
{"type":"assistant","uuid":"00000000-0000-4000-8000-000000000006","sessionId":"$session_id","timestamp":"2026-10-31T10:00:50.000Z","message":{"id":"msg_03","role":"assistant","model":"claude-eval","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"toolu_03","name":"Skill","input":{"skill":"review:code-review"}}]}}
{"type":"user","uuid":"00000000-0000-4000-8000-000000000007","sessionId":"$session_id","timestamp":"2026-10-31T10:01:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_03","content":"One finding in notes.md."}]}}
{"type":"assistant","uuid":"00000000-0000-4000-8000-000000000008","sessionId":"$session_id","timestamp":"2026-10-31T10:01:10.000Z","message":{"id":"msg_04","role":"assistant","model":"claude-eval","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"toolu_04","name":"Skill","input":{"skill":"source-control:commit"}}]}}
{"type":"user","uuid":"00000000-0000-4000-8000-000000000009","sessionId":"$session_id","timestamp":"2026-10-31T10:01:20.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_04","content":"Committed the fix."}]}}
{"type":"assistant","uuid":"00000000-0000-4000-8000-000000000010","sessionId":"$session_id","timestamp":"2026-10-31T10:01:30.000Z","message":{"id":"msg_05","role":"assistant","model":"claude-eval","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"toolu_05","name":"Skill","input":{"skill":"source-control:commit"}}]}}
{"type":"user","uuid":"00000000-0000-4000-8000-000000000011","sessionId":"$session_id","timestamp":"2026-10-31T10:01:40.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_05","content":"Committed the changelog."}]}}
{"type":"assistant","uuid":"00000000-0000-4000-8000-000000000012","sessionId":"$session_id","timestamp":"2026-10-31T10:01:50.000Z","message":{"id":"msg_06","role":"assistant","model":"claude-eval","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"text","text":"All three commits are in."}]}}
EOF

cat >.work/running-retros/2026-10-31-running-retro-eval.md <<EOF
---
session_id: $session_id
plugin_usage: {"skills": {"source-control:commit": 3, "review:code-review": 1, "docs-hygiene:compress": 1}}
---

## Checkpoint

The notes file was compressed, reviewed once, and committed in three steps.
EOF
