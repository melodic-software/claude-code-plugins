# The built-in `WebFetch` and `WebSearch` tools: verification record

Detail behind the Boundary section in [SKILL.md](../SKILL.md). Each row is a four-part record:
the claim, the basis it rests on, the date it was checked, and the event that makes it worth
checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `WebFetch` and `WebSearch` are built-in tools, model-invocable, gated, and deferred (they load through tool search) | The `/harness-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_tools.WebFetch`, `builtin_tools.WebSearch`) | 2026-09-29 | A release renames or removes either tool, or changes its gating or loading |
| `WebFetch` converts the page to Markdown and runs the prompt against it with a small, fast model, so Claude usually receives that model's answer, not the raw page; it refuses `localhost` and dotless hosts | <https://code.claude.com/docs/en/tools-reference>, "WebFetch tool behavior" | 2026-09-29 | The page changes how WebFetch returns content |
| `WebSearch` returns result titles and URLs and does not fetch the result pages | Same page, "WebSearch tool behavior" | 2026-09-29 | The page changes what WebSearch returns |

## Why the verdict is complementary

The built-in tools are the cheap default for a readable page or a quick lookup. This skill covers
what they do not: pages behind anti-bot layers or JS, full-text capture to disk, crawling, and
browser interaction. Each keeps its lane.
