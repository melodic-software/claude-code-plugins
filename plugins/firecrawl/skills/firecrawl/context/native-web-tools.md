# The built-in `WebFetch` and `WebSearch` tools: verification record

Detail behind the Boundary section in [SKILL.md](../SKILL.md). Each row is a four-part record:
the claim, the basis it rests on, the date it was checked, and the event that makes it worth
checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `WebFetch` and `WebSearch` are built-in tools, model-invocable, gated, and deferred (they load through tool search) | The `/harness-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_tools.WebFetch`, `builtin_tools.WebSearch`) | 2026-09-29 | A release renames or removes either tool, or changes its gating or loading |
| What `WebFetch` returns and which hosts it refuses, which decides when a page needs this skill instead | Pointer: when choosing between `WebFetch` and this skill, fetch [WebFetch tool behavior](https://code.claude.com/docs/en/tools-reference#webfetch-tool-behavior) live | 2026-10-11 | That section changes how WebFetch returns content or which hosts it refuses |
| What `WebSearch` returns, which decides when a search needs this skill's `search` instead | Pointer: when choosing between `WebSearch` and this skill, fetch [WebSearch tool behavior](https://code.claude.com/docs/en/tools-reference#websearch-tool-behavior) live | 2026-10-11 | That section changes what WebSearch returns |

## Why the verdict is complementary

The built-in tools are the cheap default for a readable page or a quick lookup. This skill covers
what they do not: pages behind anti-bot layers or JS, full-text capture to disk, crawling, and
browser interaction. Each keeps its lane.
