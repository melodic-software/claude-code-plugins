---
description: Improve and optimize prompts using Anthropic's 4-step prompt improvement workflow
argument-hint: [prompt text | file path | 'context' | 'iterate'] [--feedback "..."] [--generate-examples]
allowed-tools: Read, Write, Glob, Task, Skill
---

# Improve Prompt Command

You are tasked with improving prompts using Anthropic's prompt improvement methodology.

## Command Arguments

This command accepts **input modes and optional flags**:

### Input Modes (Required - one of)

1. **Direct text**: Prompt text provided inline
   - Example: `/improve-prompt "Classify this email as spam or not spam"`

2. **File path**: Path to a file containing the prompt
   - Example: `/improve-prompt ./prompts/classifier.md`
   - Supports: `.md`, `.txt`, `.prompt`, `.xml`

3. **'context'**: Extract prompt from recent conversation context
   - Example: `/improve-prompt context`
   - Uses the most recent prompt discussed in conversation

4. **'iterate'**: Re-improve a previously improved prompt
   - Example: `/improve-prompt iterate`
   - Continues refinement of the last improved prompt

### Optional Flags

- `--feedback "..."`: Provide specific feedback for targeted refinement
  - Example: `/improve-prompt iterate --feedback "CoT is too verbose"`

- `--generate-examples`: Auto-generate test cases if prompt lacks examples
  - Example: `/improve-prompt "Classify sentiment" --generate-examples`

## Workflow

### Step 1: Parse Input Mode

1. **Check for flags** first:
   - Extract `--feedback "..."` if present
   - Check for `--generate-examples` flag

2. **Detect input mode**:

   ```text
   IF argument starts with quote or contains prompt text:
     mode = "direct_text"
     prompt = argument text
   ELSE IF argument is valid file path:
     mode = "file"
     prompt = read file contents
   ELSE IF argument is "context":
     mode = "context"
     prompt = extract from conversation history
   ELSE IF argument is "iterate":
     mode = "iterate"
     prompt = load last improved prompt from session
   ELSE:
     mode = "direct_text" (assume inline prompt)
   ```

3. **Validate input**:
   - For file mode: Verify file exists and is readable
   - For context mode: Verify prompt is identifiable in history
   - For iterate mode: Verify previous improvement exists

### Step 2: Invoke Prompt Improver Agent

Spawn the prompt-improver subagent with appropriate context:

```text
Use the prompt-improver subagent to improve the following prompt.

## Input Mode
{mode description}

## Original Prompt
{prompt text}

## Context
{any relevant context from conversation}

## Flags
- Generate examples: {yes/no}
- Feedback: {feedback text or "none"}

## Instructions
Apply the 4-step prompt improvement workflow:
1. Example Identification
2. Initial Draft (XML structure)
3. Chain of Thought Refinement
4. Example Enhancement

{If iterate mode}: Focus on targeted refinements based on feedback.
{If generate-examples}: Generate 2-3 test cases before improvement.

Return the improved prompt with explanation of changes.
```

### Step 3: Present Results

After agent completes, present results to user:

```markdown
## Prompt Improvement Complete

### Input Mode
{mode used}

### Summary
{brief description of improvements made}

### Before → After Comparison

| Aspect | Before | After |
|--------|--------|-------|
| Structure | {before} | {after} |
| Examples | {count} | {count} |
| CoT Level | {level} | {level} |

### Improved Prompt

{The complete improved prompt}

### Next Steps
- **Test**: Try the improved prompt with sample inputs
- **Iterate**: Use `/improve-prompt iterate --feedback "..."` for refinement
- **Save**: Copy the improved prompt to your project

### Trade-off Notes
{Any latency/cost implications}
```

### Step 4: Track for Iteration

If user may want to iterate:

1. **Store improved prompt** in session context
2. **Note iteration count** (first improvement = iteration 1)
3. **Enable iterate mode** for follow-up commands

## Example Usage

### Example 1: Direct Text Input

```text
User: /improve-prompt "Summarize this article in 3 sentences"

Claude: [Invokes prompt-improver agent]

## Prompt Improvement Complete

### Input Mode
Direct text input

### Summary
Added XML structure, explicit constraints, and example with reasoning.

### Improved Prompt

<instructions>
You are a professional summarizer. Create a concise 3-sentence summary.

Requirements:
- Exactly 3 sentences (no more, no less)
- Capture main point, key evidence, and conclusion
- Use clear, direct language
</instructions>

<article>
{{article}}
</article>

<formatting>
First identify key points in <thinking> tags.
Then provide exactly 3 sentences in <summary> tags.
</formatting>

### Next Steps
Use `/improve-prompt iterate --feedback "..."` to refine further.
```

### Example 2: File Input

```text
User: /improve-prompt ./prompts/email-classifier.md

Claude: Reading prompt from file...

[Invokes prompt-improver agent]

## Prompt Improvement Complete

### Input Mode
File: ./prompts/email-classifier.md

[Rest of improvement report]
```

### Example 3: Iterate with Feedback

```text
User: /improve-prompt iterate --feedback "The chain of thought is too verbose, make it more concise"

Claude: [Invokes prompt-improver agent in iterate mode]

## Prompt Refinement Complete (Iteration 2)

### Feedback Applied
"The chain of thought is too verbose, make it more concise"

### Changes Made
- Reduced CoT from structured to guided
- Limited thinking to 3-5 bullet points
- Simplified example reasoning

[Updated improved prompt]
```

### Example 4: Generate Examples

```text
User: /improve-prompt "Classify customer feedback" --generate-examples

Claude: [Invokes prompt-improver agent with example generation]

## Prompt Improvement Complete

### Generated Test Cases
Before improvement, generated 3 test cases:
1. Typical positive feedback
2. Typical negative feedback
3. Edge case (mixed sentiment)

[Improved prompt with examples]
```

## Error Handling

### File Not Found

```text
Error: Could not find file at path: {path}

Please check:
- The file path is correct
- The file exists and is readable
- Use absolute path if relative path fails
```

### No Context Available

```text
Error: Could not identify a prompt in recent conversation.

Please either:
- Provide the prompt text directly
- Provide a file path
- Ensure a prompt was recently discussed
```

### No Previous Improvement

```text
Error: No previous prompt improvement found for iteration.

Please use one of these modes first:
- /improve-prompt "your prompt text"
- /improve-prompt ./path/to/prompt.md
- /improve-prompt context
```

## Notes

- **Subagent handles the improvement** - this command is the orchestrator
- **Prompt-improvement skill is auto-loaded** by the subagent
- **Official docs accessed via docs-management** through the skill chain
- **Iterate mode preserves context** across multiple refinement passes
- **Trade-offs are reported** to help users make informed decisions
