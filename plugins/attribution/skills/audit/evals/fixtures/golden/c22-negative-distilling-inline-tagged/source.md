# Prompting Claude Sonnet 5

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the page named next, and nothing else from that page is reproduced.

Canonical location for the purposes of this case: `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5`.

## Calibrating effort and thinking depth

On Claude Sonnet 5, [adaptive thinking](https://platform.claude.com/docs/en/build-with-claude/thinking) is on by default. Requests without a `thinking` field run with adaptive thinking. This is a change from Claude Sonnet 4.6, where the same requests ran without thinking. To turn thinking off entirely, pass `thinking: {type: "disabled"}`. Because `max_tokens` is a hard limit on total output (thinking plus response text), revisit it for workloads that ran without thinking on Claude Sonnet 4.6. If you were previously using thinking off with Claude Sonnet 4.6, try thinking on with lower effort levels for Claude Sonnet 5.

The triggering behavior for adaptive thinking is steerable. If you find the model emitting thinking blocks more often than you'd like, which can happen with large or complex system prompts, add guidance to steer it. As always, measure the effect of any prompting changes on performance.
