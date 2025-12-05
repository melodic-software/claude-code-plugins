# Composable Agentic Primitives: The Secret of TAC

## The Secret

> "The secret of tactical agentic coding is that it's not about the software developer lifecycle at all. It's about composable agentic primitives you can use to solve any engineering problem class."

## What This Means

The SDLC (Plan -> Build -> Test -> Review -> Document -> Ship) is just ONE composition of primitives. Different organizations, problem classes, and contexts require different compositions.

## The Primitives

Individual building blocks that can be combined:

| Primitive | Purpose | Input | Output |
| ----------- | --------- | ------- | -------- |
| **Plan** | Create implementation spec | Issue/task | Plan file |
| **Build** | Implement the plan | Plan file | Code changes |
| **Test** | Validate functionality | Code changes | Pass/fail result |
| **Review** | Validate alignment to spec | Spec + code | Issue list |
| **Patch** | Fix specific issues | Issue description | Targeted fix |
| **Document** | Generate documentation | Code changes | Doc files |
| **Ship** | Deploy to production | Validated code | Deployed state |
| **Classify** | Categorize input | Issue/task | Classification |
| **Branch** | Create isolated context | Classification | Branch name |
| **Commit** | Save checkpoint | Changes | Commit hash |

## Example Compositions

### Standard SDLC

```text
Classify -> Plan -> Build -> Test -> Review -> Document -> Ship
```markdown

Full lifecycle for features.

### Quick Fix

```text
Classify -> Patch -> Test -> Ship
```markdown

Bypass planning for obvious fixes.

### Documentation Sprint

```text
Classify -> Document -> Review -> Ship
```markdown

Documentation-only changes.

### Experimental

```text
Plan -> Build -> Test
```markdown

No shipping, just exploration.

### Continuous Improvement

```text
Review -> Patch -> Test -> Ship
```markdown

Review-driven refinement.

## Composition Principles

### 1. Start with the Problem Class

Different problems need different compositions:

| Problem Class | Typical Composition |
| --------------- | --------------------- |
| Chore | Classify -> Build -> Test -> Ship |
| Bug | Classify -> Plan -> Build -> Test -> Review -> Ship |
| Feature | Full SDLC |
| Hotfix | Patch -> Test -> Ship |
| Refactor | Plan -> Build -> Test -> Review |

### 2. Match Composition to Confidence

| Confidence Level | Composition Strategy |
| ------------------ | --------------------- |
| Low | Include Review, manual shipping |
| Medium | Include Review, automated shipping |
| High | Skip Review, automated shipping (ZTE) |

### 3. Organization-Specific Compositions

Your organization has unique:

- Testing requirements
- Review processes
- Documentation standards
- Deployment pipelines
- Compliance needs

Build compositions that embed YOUR practices.

## Building Your Own Compositions

### Step 1: Identify Primitives Needed

What operations does your workflow require?

### Step 2: Order by Dependencies

Which primitives depend on others' outputs?

### Step 3: Add Validation Points

Where do failures need to stop the pipeline?

### Step 4: Define Entry/Exit Criteria

What triggers the workflow? What signals completion?

## The Power of Primitives

**Flexibility:**

- Same primitives, different orders
- Add/remove primitives as needed
- Customize per problem class

**Reusability:**

- Build once, compose many ways
- Each primitive is independently testable
- Improvements to one benefit all compositions

**Scalability:**

- Compositions can run in parallel
- Different problem classes use different compositions
- Multiple workflows can share primitives

## Anti-Patterns

**Rigid SDLC thinking:**

- "We must always do all steps"
- Not all changes need full SDLC
- Match composition to task

**Primitive soup:**

- Random combinations without structure
- No clear entry/exit criteria
- Missing validation points

**Over-composition:**

- Too many primitives for simple tasks
- Complexity without benefit
- Bureaucratic overhead

## Key Insight

> "Each organization will have unique primitive compositions. AI workflows will outperform traditional approaches as we move away from rigid development lifecycles to flexible primitive composition."

The goal is to build a library of primitives and the wisdom to compose them effectively.

## Cross-References

- @zte-progression.md - How ZTE uses primitives
- @template-engineering.md - Templates as primitive definitions
- @adw-anatomy.md - ADW as a composition framework
