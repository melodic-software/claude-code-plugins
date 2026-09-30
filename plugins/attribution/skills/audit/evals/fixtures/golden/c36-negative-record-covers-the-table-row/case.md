# Checklist for runner plugin audits

The limits restated in criterion W7 (the 20,000-token output default and the 500,000-character
ceiling) are the runner's, not ours. Basis:
<https://example.invalid/widget-runner/docs/plugins#output-limits>. Verified 2026-09-20 against
runner 2.4. Recheck trigger: that section moving either number, or a release note naming the
output limit, re-derives W7 and this record.

| # | Criterion | Severity | How to evaluate |
|---|-----------|----------|-----------------|
| W6 | **Plugin declares its cache scope**. | WARN | Missing scope = WARN: the runner treats the plugin as workspace-wide. |
| W7 | **Plugin sets `maxOutputChars` on large-output tools**. | info (WARN if set ineffectively) | Missing on a large-output tool = info: output over the default limit is written to disk and replaced with a file reference. Set, the runner raises that tool's limit to the declared value, up to a hard ceiling of 500,000 characters, independently of `WIDGET_MAX_OUTPUT_TOKENS`. Set above 500,000 = WARN, the excess never applies. |
| W8 | **Plugin names its required runner version**. | info | Missing = info. A floor above the fleet's runner = FAIL. |

Score each row independently and report the worst severity per plugin.
