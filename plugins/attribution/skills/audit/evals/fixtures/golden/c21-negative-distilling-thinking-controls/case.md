## Thinking controls

On Claude Opus 4.8 thinking is OFF unless the request explicitly sets `thinking: {type: "adaptive"}`, and adaptive thinking's triggering behavior is steerable by prompt. A large or complex system prompt can make it fire more often than wanted. `[CC: API-side]` This is a fact about API requests, not about your Claude Code session: the harness owns thinking there through its own controls ([model config](https://code.claude.com/docs/en/model-config)), so do not read a thinking-off default into a session you did not configure.

## Sources

Official Anthropic prompting guides, fetched 2026-07-06:

- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8>: literalism, effort strictness, tool-use triggering, subagent spawning, review-recall harness effect, progress updates, response-length calibration, adaptive-thinking default, max-output-token budget at high effort
- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>: strong instruction following, act-when-enough-info, grounded progress claims, boundaries, parallel-subagent readiness, memory-system guidance, final-summary readability
