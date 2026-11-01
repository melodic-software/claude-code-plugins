#!/usr/bin/env bash
set -euo pipefail
sid=f47b1a02-c5e9-4d36-92ab-8d10e6c3f75e
transcript=session-data/$sid.jsonl
mkdir -p session-data
n=0
fields() {
  n=$((n + 1))
  rec=$(printf '"uuid":"rec-%03d","sessionId":"%s","timestamp":"2026-10-31T%s:00Z","cwd":"/srv/app","gitBranch":"fix/pagination","version":"2.1.312"' "$n" "$sid" "$1")
}
typed() {
  fields "$1"
  printf '{"type":"user",%s,"message":{"role":"user","content":"%s"}}\n' "$rec" "$2" >>"$transcript"
}
says() {
  fields "$1"
  printf '{"type":"assistant",%s,"message":{"id":"msg-%03d","role":"assistant","model":"claude-sonnet-5","stop_reason":"end_turn","usage":{"input_tokens":900,"output_tokens":60},"content":[{"type":"text","text":"%s"}]}}\n' "$rec" "$n" "$2" >>"$transcript"
}
skill() {
  fields "$1"
  printf '{"type":"assistant",%s,"message":{"id":"msg-%03d","role":"assistant","model":"claude-sonnet-5","stop_reason":"tool_use","usage":{"input_tokens":900,"output_tokens":60},"content":[{"type":"tool_use","id":"tool-%03d","name":"Skill","input":{"skill":"%s"}}]}}\n' "$rec" "$n" "$n" "$2" >>"$transcript"
  local id=$n
  fields "$1"
  printf '{"type":"user",%s,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-%03d","content":"Launching skill: %s"}]}}\n' "$rec" "$id" "$2" >>"$transcript"
}
command_typed() {
  fields "$1"
  printf '{"type":"user",%s,"message":{"role":"user","content":"<command-name>/%s</command-name>"}}\n' "$rec" "$2" >>"$transcript"
}

typed 11:02 "Patch the export bug and commit it."
skill 11:10 source-control:commit
command_typed 11:18 toolchain:check
skill 11:33 source-control:commit
skill 11:47 toolchain:check
skill 12:05 source-control:commit
says 12:09 "Everything is committed."
