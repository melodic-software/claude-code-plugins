---
description: Improve and optimize prompts using Anthropic's 4-step prompt improvement workflow
argument-hint: [prompt text | file path | 'context' | 'iterate'] [--feedback "..."] [--generate-examples]
allowed-tools: Read, Write, Glob, Task, Skill
---

# Improve Prompt Command

You are tasked with improving prompts using Anthropic's prompt improvement methodology.

## Quick Reference

**Decision Tree: Which Input Mode?**

```text
Do you have a prompt in a file? -> Use file path mode
Did we just discuss a prompt? -> Use 'context' mode
Refining previous improvement? -> Use 'iterate' mode
Have prompt text ready? -> Use direct text mode
```

**Quality Criteria (What Makes a Good Improvement):**

- [ ] XML tags organize components clearly
- [ ] Chain of thought matches task complexity
- [ ] Examples demonstrate reasoning process
- [ ] Output format is explicit and unambiguous
- [ ] Instructions are clear and direct
- [ ] No over-engineering for simple tasks

**Edge Cases to Handle:**

- **Already-good prompt**: Report minimal improvement needed, suggest small refinements
- **Empty/minimal prompt**: Use `--generate-examples` or suggest starting with prompt generator
- **Over-engineered prompt**: Simplify rather than add complexity
- **Ambiguous task**: Ask clarifying questions before improving

---

## Command Arguments

This command accepts **input modes and optional flags**:

### Input Modes (Required - one of)

1. **Direct text**: Prompt text provided inline
   - Example: `/improve-prompt "Classify this email as spam or not spam"`
   - **Use when**: You have prompt text ready to paste

2. **File path**: Path to a file containing the prompt
   - Example: `/improve-prompt ./prompts/classifier.md`
   - Supports: `.md`, `.txt`, `.prompt`, `.xml`
   - **Use when**: Prompt is stored in a file

3. **'context'**: Extract prompt from recent conversation context
   - Example: `/improve-prompt context`
   - Uses the most recent prompt discussed in conversation
   - **Use when**: You just discussed a prompt and want it improved

4. **'iterate'**: Re-improve a previously improved prompt
   - Example: `/improve-prompt iterate`
   - Continues refinement of the last improved prompt
   - **Use when**: Refining based on feedback

### Optional Flags

- `--feedback "..."`: Provide specific feedback for targeted refinement
  - Example: `/improve-prompt iterate --feedback "CoT is too verbose"`
  - **Use when**: You know exactly what needs adjustment

- `--generate-examples`: Auto-generate test cases if prompt lacks examples
  - Example: `/improve-prompt "Classify sentiment" --generate-examples`
  - **Use when**: Prompt has no examples and task needs demonstrations

---

## Workflow

### Step 1: Parse Input Mode

**Goal:** Identify input mode, extract flags, validate input

**Process:**

1. **Extract flags first**:
   - Check for `--feedback "..."` (extract quoted text)
   - Check for `--generate-examples` (boolean flag)

2. **Detect input mode** (priority order):

   ```text
   IF argument is valid file path:
     mode = "file"
     prompt = read file contents
     Validate: file exists and is readable
   ELSE IF argument is "context":
     mode = "context"
     prompt = extract from conversation history
     Validate: prompt identifiable in recent messages
   ELSE IF argument is "iterate":
     mode = "iterate"
     prompt = load last improved prompt from session
     Validate: previous improvement exists in session
   ELSE:
     mode = "direct_text"
     prompt = argument text (strip quotes if present)
     Validate: prompt is not empty
   ```

3. **Edge case detection**:
   - Empty or minimal prompt -> Suggest `--generate-examples` or prompt generator
   - Very long prompt -> Note potential for token optimization
   - Already well-structured prompt -> Flag for minimal improvement

**Checkpoint:**

- [ ] Input mode identified correctly
- [ ] Flags extracted (if present)
- [ ] Input validated
- [ ] Edge cases detected

---

### Step 2: Invoke Prompt Improver Agent

**Goal:** Spawn prompt-improver subagent with structured instructions

**Agent Prompt Template:**

```text
Improve the following prompt using Anthropic's 4-step workflow.

## Input Context

**Mode:** {mode description}
**Source:** {file path, context reference, or iteration number}
{If iterate mode: **Feedback:** {feedback text}}
{If generate-examples: **Generate Examples:** Yes (create 2-3 test cases before improvement)}

## Original Prompt

{prompt text}

## Instructions: Apply 4-Step Improvement Workflow

### Step 1: Example Identification

- Extract any existing examples from the prompt
- Note format and structure of current examples
- Identify if examples are missing
- For iterate mode: Review how current examples perform

**Checkpoint:**
- [ ] Existing examples documented
- [ ] Example format noted
- [ ] Missing examples identified

### Step 2: Initial Draft (XML Structure)

- Wrap prompt components in XML tags:
  - `<instructions>` for task definition
  - `<context>` for background (if needed)
  - `<examples>` for demonstrations
  - `<formatting>` for output specification
- Use consistent tag naming throughout
- Place variable inputs in appropriate tags

**Checkpoint:**
- [ ] All components have appropriate XML tags
- [ ] Tag naming is consistent
- [ ] Variable sections clearly marked

### Step 3: Chain of Thought Refinement

- Assess task complexity
- Choose CoT level:
  - Basic: Simple "think step-by-step" instruction
  - Guided: Specific reasoning steps listed
  - Structured: XML-tagged thinking with `<thinking>` and `<answer>` tags
- Add thinking instructions appropriate to complexity
- Specify separation between reasoning and output

**Checkpoint:**
- [ ] CoT level matches task complexity
- [ ] Reasoning process explicitly requested
- [ ] Thinking separated from final answer

### Step 4: Example Enhancement

- Add `<thinking>` sections to all examples
- Show step-by-step analysis in examples
- Connect reasoning to final output
- Ensure examples match output format specification

**Checkpoint:**
- [ ] All examples include reasoning
- [ ] Examples demonstrate expected approach
- [ ] Format matches instructions

## Quality Criteria

Verify the improved prompt meets these criteria:

- [ ] XML tags organize components clearly
- [ ] Chain of thought matches task complexity
- [ ] Examples demonstrate reasoning process
- [ ] Output format is explicit and unambiguous
- [ ] Instructions are clear and direct
- [ ] No over-engineering for simple tasks

## Output Format

Provide:

1. **Analysis**: What was improved and why
2. **Before/After Comparison**: Table showing structure, examples, CoT level
3. **Improved Prompt**: Complete prompt ready for use
4. **Trade-off Notes**: Any latency/cost implications
5. **Next Steps**: Suggestions for testing or iteration
```

**Checkpoint:**

- [ ] Agent spawned with Task tool
- [ ] Subagent type: "general-purpose"
- [ ] Description: "Improve prompt using 4-step workflow"
- [ ] Prompt includes all required sections

---

### Step 3: Present Results

**Goal:** Format agent output for user clarity

**Output Template:**

````markdown
## Prompt Improvement Complete

### Input Mode
{mode used} {if file: show path} {if iterate: show iteration number}

### Summary
{1-2 sentence description of improvements made}

### Before → After Comparison

| Aspect | Before | After |
|--------|--------|-------|
| Structure | {before} | {after} |
| Examples | {count} | {count} |
| CoT Level | {none/basic/guided/structured} | {level} |
| Format Spec | {implicit/explicit} | {explicit with tags} |

### Improved Prompt

```{language}
{The complete improved prompt}
```

### Trade-offs

{Any latency/cost implications, or "No significant trade-offs for this improvement"}

### Recommendations

**Recommended:**

1. **Test**: Try the improved prompt with sample inputs
2. **Iterate**: Use `/improve-prompt iterate --feedback "..."` for refinement
3. **Save**: Copy the improved prompt to your project

**Optional:**

- Compare outputs between original and improved prompts
- Run A/B testing with real use cases
- Share with team for feedback
````

**Checkpoint:**

- [ ] Agent output received
- [ ] Results formatted for clarity
- [ ] Before/After comparison included
- [ ] Complete improved prompt provided
- [ ] Trade-offs noted
- [ ] Next steps suggested

---

### Step 4: Track for Iteration

**Goal:** Enable iterate mode for follow-up refinements

**Process:**

1. **Store in session context**:
   - Save improved prompt text
   - Save iteration count (1, 2, 3, ...)
   - Save any feedback applied

2. **Enable iterate mode**:
   - User can run `/improve-prompt iterate`
   - User can add `--feedback "..."` for targeted changes

3. **Session state tracking**:
   - Original prompt (iteration 0)
   - Improved prompt (iteration 1)
   - Refined prompt (iteration 2+)

**Checkpoint:**

- [ ] Improved prompt stored for iteration
- [ ] Iteration count tracked
- [ ] Iterate mode enabled

---

## Verification Protocol (Before Reporting Complete)

### CRITICAL: Verify ALL Steps Before Reporting Completion

Before saying "done," check:

- [ ] **Step 1**: Input parsed and validated
- [ ] **Step 2**: Agent spawned with complete instructions
- [ ] **Step 2.5**: Agent completed successfully (received Task tool output)
- [ ] **Step 3**: Results formatted and presented
- [ ] **Step 4**: Session state updated for iteration
- [ ] **Quality**: Improved prompt meets quality criteria
- [ ] **Edge cases**: Any special cases handled appropriately

**If ANY checkbox is unchecked, complete that step before reporting done.**

---

## Example Usage

### Example 1: Direct Text Input

````text
User: /improve-prompt "Summarize this article in 3 sentences"

Claude: [Invokes prompt-improver agent]

## Prompt Improvement Complete

### Input Mode
Direct text input

### Summary
Added XML structure, explicit constraints, chain of thought for summary construction, and example with reasoning.

### Before → After Comparison

| Aspect | Before | After |
|--------|--------|-------|
| Structure | Single sentence | XML-tagged components |
| Examples | 0 | 1 |
| CoT Level | None | Guided (identify key points) |
| Format Spec | Implicit | Explicit with `<summary>` tags |

### Improved Prompt

```xml
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
First identify key points in <thinking> tags:
- Main claim or thesis
- Supporting evidence
- Key conclusion

Then provide exactly 3 sentences in <summary> tags.
</formatting>

<examples>
  <example>
    <input>
      [Article about climate change impact]
    </input>
    <thinking>
      Main claim: Rising temperatures affect ecosystems
      Supporting evidence: Polar ice melting, species migration
      Conclusion: Urgent action needed
    </thinking>
    <summary>
      Global temperatures are rising at unprecedented rates, causing polar ice to melt and species to migrate to cooler regions. Scientists have documented these changes across multiple ecosystems worldwide. Immediate action is required to mitigate further environmental damage.
    </summary>
  </example>
</examples>
```

### Trade-off Analysis

Structured thinking may add 10-20% latency but significantly improves summary quality.

### Iteration Suggestion

Use `/improve-prompt iterate --feedback "..."` to refine further.
````

---

### Example 2: File Input

```text
User: /improve-prompt ./prompts/email-classifier.md

Claude: Reading prompt from file: ./prompts/email-classifier.md

[Invokes prompt-improver agent]

## Prompt Improvement Complete

### Input Mode
File: ./prompts/email-classifier.md

### Summary
Restructured with XML tags, added chain of thought for classification reasoning, and enhanced examples with step-by-step analysis.

[Rest of improvement report]
```

---

### Example 3: Iterate with Feedback

```text
User: /improve-prompt iterate --feedback "The chain of thought is too verbose, make it more concise"

Claude: [Invokes prompt-improver agent in iterate mode]

## Prompt Refinement Complete (Iteration 2)

### Input Mode
Iterate mode (refinement)

### Feedback Applied
"The chain of thought is too verbose, make it more concise"

### Changes Made
- Reduced CoT from structured to guided
- Limited thinking to 3-5 bullet points
- Simplified example reasoning to key considerations only

### Before → After Comparison (Iteration 1 → 2)

| Aspect | Iteration 1 | Iteration 2 |
|--------|-------------|-------------|
| CoT Level | Structured (detailed `<thinking>`) | Guided (concise bullets) |
| Example Reasoning | 7-10 lines per example | 3-5 lines per example |
| Token Count | ~850 tokens | ~620 tokens (27% reduction) |

[Updated improved prompt]

### Trade-off Notes
Concise CoT reduces latency by ~20% while maintaining accuracy for this task.
```

---

### Example 4: Generate Examples

```text
User: /improve-prompt "Classify customer feedback" --generate-examples

Claude: [Invokes prompt-improver agent with example generation]

## Prompt Improvement Complete

### Input Mode
Direct text with example generation

### Summary
Generated 3 test cases (positive, negative, mixed), then improved prompt with XML structure, guided CoT, and examples enriched with reasoning.

### Generated Test Cases

Before improvement, created 3 representative examples:
1. **Positive feedback**: "Love the new features! App works perfectly."
2. **Negative feedback**: "Terrible experience. App crashes constantly."
3. **Mixed feedback**: "Good features but too expensive for what it offers."

### Before → After Comparison

| Aspect | Before | After |
|--------|--------|-------|
| Structure | Single sentence | XML-tagged components |
| Examples | 0 (generated 3) | 3 with reasoning |
| CoT Level | None | Guided (sentiment indicators) |
| Format Spec | Implicit | Explicit JSON structure |

[Improved prompt with generated examples]
```

---

## Error Handling

### File Not Found

```text
Error: Could not find file at path: {path}

Please check:
- The file path is correct
- The file exists and is readable
- Use absolute path if relative path fails

Suggestion: Use `/improve-prompt "your prompt text"` to provide directly.
```

---

### No Context Available

```text
Error: Could not identify a prompt in recent conversation.

The 'context' mode requires a prompt to have been recently discussed.

Please either:
- Provide the prompt text directly: `/improve-prompt "your prompt"`
- Provide a file path: `/improve-prompt ./path/to/prompt.md`
- Ensure a prompt was recently discussed in this conversation
```

---

### No Previous Improvement

```text
Error: No previous prompt improvement found for iteration.

The 'iterate' mode requires a previous improvement in this session.

Please use one of these modes first:
- `/improve-prompt "your prompt text"`
- `/improve-prompt ./path/to/prompt.md`
- `/improve-prompt context`

Then you can use `/improve-prompt iterate` to refine.
```

---

### Empty or Minimal Prompt

```text
Warning: The provided prompt is very minimal ("{prompt text}").

Recommendations:
1. Use `--generate-examples` to create test cases first
2. Clarify the task definition before improving
3. Consider using the prompt generator tool for initial draft

Would you like to:
- Add `--generate-examples` flag and proceed?
- Provide more context about the task?
- Cancel and revise the prompt?
```

---

## Notes

- **Subagent handles the improvement** - this command is the orchestrator
- **Prompt-improvement skill is auto-loaded** by the subagent
- **Official docs accessed via docs-management** through the skill chain
- **Iterate mode preserves context** across multiple refinement passes
- **Trade-offs are reported** to help users make informed decisions
- **Quality criteria enforce best practices** from Anthropic's methodology
- **Edge cases are explicitly handled** to avoid poor outcomes
- **Verification protocol prevents** incomplete execution (context collapse prevention)
