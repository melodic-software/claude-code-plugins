# Testing Skills Workflow

Step-by-step workflow for testing skill activation and functionality.

## Official Documentation Query

For complete testing guidance, query official-docs:

```text
Find documentation about skill testing using keywords: skill testing, activation testing, test scenarios
```

## Workflow Overview

**High-Level Steps:**

1. **Define Test Scenarios** → Create 3-5 test cases
2. **Test Basic Activation** → Direct skill invocation
3. **Test Contextual Activation** → Domain/task triggers
4. **Test Edge Cases** → Unusual inputs
5. **Multi-Model Testing** → Test with different models (optional)

## Detailed Workflow

### Step 1: Define Test Scenarios

Query official-docs: "Find skill testing best practices and scenario development"

**Create 3-5 scenarios covering:**

- Basic activation (direct mention)
- Contextual activation (domain/task)
- Edge cases
- Expected output
- Error handling

### Step 2: Test Basic Activation

Query official-docs: "Find skill activation testing procedures"

**Pattern:**

```markdown
### Test 1: Basic Activation
**Query:** "Use the [skill-name] skill to..."
**Expected:** Skill activates and follows instructions
**Result:** [✅ PASS / ❌ FAIL]
```

### Step 3: Test Contextual Activation

**Test with varied phrasings:**

1. Domain: "[domain from description]"
2. Task: "I need to [task from description]"
3. File type: "I have a [file type from description]"

### Step 4: Test Edge Cases

Query official-docs: "Find skill edge case testing and error handling"

**Examples:**

- Missing required inputs
- Invalid inputs
- Unexpected file types
- Boundary conditions

### Step 5: Multi-Model Testing (Optional)

Query official-docs: "Find multi-model testing strategies"

**Test with:**

- Sonnet (standard)
- Haiku (reduced context)
- Opus (complex tasks)

## Test Documentation Pattern

```markdown
### Test Scenario N: [Name]

**Query:** "[exact test query]"
**Expected Behavior:** [what should happen]
**Success Criteria:** [how to measure success]
**Actual Result:** [what actually happened]
**Status:** [✅ PASS / ❌ FAIL]
**Notes:** [any observations]
```

## Common Queries

**For test scenario development:**
**Query official-docs:** "Find skill testing best practices and test case patterns"

**For activation troubleshooting:**
**Query official-docs:** "Find skill activation debugging and troubleshooting"

**For multi-model testing:**
**Query official-docs:** "Find multi-model testing strategies and considerations"

For all testing details, query official-docs with the patterns above.
