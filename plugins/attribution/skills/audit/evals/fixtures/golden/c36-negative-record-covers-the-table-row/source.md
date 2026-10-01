# Widget Runner: plugin output limits

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/plugins`.

## Output limits

When a plugin tool's output goes over the default limit, the runner writes it to disk and replaces
it with a file reference. A tool can declare `maxOutputChars` to raise its own limit, up to a hard
ceiling of 500,000 characters, independently of `WIDGET_MAX_OUTPUT_TOKENS`. A value above the
ceiling is accepted and the excess never applies.
