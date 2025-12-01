# Model Identification

## Why This Matters

Claude Code sessions can run on different models (Opus, Sonnet, Haiku), and which model is active affects:

- **Audit metadata accuracy** - Skills and reports should reflect the actual model used
- **Capability expectations** - Different models have different strengths
- **Cost/performance tradeoffs** - Model selection impacts both

**The Problem**: Training cutoffs and default assumptions can cause incorrect model reporting. You might say "Sonnet" when actually running as "Opus 4.5" because of stale assumptions.

## Where Model Info Lives

Model identity is provided in your **system context**, not in memory files. Look for patterns like:

```text
You are powered by the model named Opus 4.5. The exact model ID is claude-opus-4-5-20251101.
```

Or in the `<env>` section at the end of the system prompt.

**Key locations to check:**

1. System prompt text mentioning "You are powered by..."
2. `<env>` section with model metadata
3. Any explicit model configuration in context

## When to Verify

**ALWAYS check before:**

- Writing audit metadata (Last Verified sections)
- Reporting "I am using model X" to users
- Claiming model-specific capabilities
- Writing skill/command metadata that includes model info
- Answering "what model are you?"

## Verification Pattern

1. **Search your context** for model identification strings
2. **Quote the actual value** you find (don't paraphrase from memory)
3. **If not found**, state "Model identity not specified in current context" rather than guessing

**Example - Correct:**

```text
Looking at my system context: "You are powered by the model named Opus 4.5.
The exact model ID is claude-opus-4-5-20251101."

I am currently running as Opus 4.5 (claude-opus-4-5-20251101).
```

**Example - Wrong:**

```text
I'm using Claude Sonnet.  <-- Assumed without checking
```

## Failure Modes

| Failure | Cause | Prevention |
| ------- | ----- | ---------- |
| Assuming Sonnet | Sonnet is common default | Check context, don't assume |
| Stale model name | Training cutoff | Read actual context value |
| Wrong version | Version confusion | Quote exact model ID |
| Not checking | Overconfidence | Make verification habitual |

## Model Reference

Current Claude model families (as of knowledge cutoff):

- **Opus 4.5** - Most capable, complex reasoning
- **Sonnet 4** / **Sonnet 4.5** - Balanced performance/cost
- **Haiku 4** / **Haiku 4.5** - Fast, efficient, simple tasks

**Always verify actual model from context rather than assuming based on these names.**

## Integration with Audits

When writing "Last Verified" sections in skills:

```markdown
**Last Verified:** 2025-11-25 (Model: claude-opus-4-5-20251101)
```

The model info should come from checking your actual context, not assumptions.

---

**Last Updated:** 2025-11-30
