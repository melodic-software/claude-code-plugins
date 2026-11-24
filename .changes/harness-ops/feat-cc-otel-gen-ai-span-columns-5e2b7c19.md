---
bump: minor
---

### Added

- add the Claude Code 2.1.331 span attributes to the `cc_spans` view and the `cc_spans_cold()`
  stub: `gen_ai_operation_name`, `gen_ai_response_model`, `gen_ai_usage_input_tokens`,
  `gen_ai_usage_output_tokens`, `gen_ai_usage_cache_read_input_tokens` and
  `gen_ai_usage_cache_write_input_tokens`

  `gen_ai_usage_input_tokens` counts cache read and write tokens, unlike `input_tokens`. Spans
  from an older Claude Code read these columns as NULL.
