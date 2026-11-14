---
type: regex
target: trace
pattern: '"subtype":"task_started"[^\n]*"task_type":"local_agent"|"type":"tool_use","id":"[^"]*","name":"(Agent|Task)"|"type":"tool_result","tool_use_id":"[^"]*","content":"Skill \\"[^"\\]*\\" completed \(forked execution\)'
---
