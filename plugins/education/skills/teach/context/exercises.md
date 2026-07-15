# Exercise Design

Exercises bridge Knowledge → Skills. Each exercise targets 1-2 specific concepts and includes a tight feedback loop. Practice colocates with its lesson in the concept slice (`concepts/<concept>/exercise.md`); a lesson may also embed a light feedback-loop task inline. This file is the design guidance for both.

## Exercise Types

| Type | When to use | Format |
|---|---|---|
| **Retrieval practice** | After explaining a concept | Ask user to restate in own words or identify correct usage from examples |
| **Code kata** (codebase mode) | After demonstrating a repo pattern | User implements a small variation using the pattern |
| **Bug hunt** | When common misconceptions exist | Present buggy code, user diagnoses and fixes |
| **Comparison** | When tradeoffs matter (wisdom layer) | Present two approaches, user argues pros/cons |
| **Transfer** | After user demonstrates skill in one context | Apply same concept in different context ("where else in the project?") |
| **Blank-filling** | When user needs scaffolded practice | Partial code with TODOs, user fills in |

## Design Rules

- **One concept per exercise** — don't combine debugging AND new syntax AND architecture in one problem
- **Immediate feedback** — user gets response right after attempt, not after a batch
- **Mission-connected** — tie exercises to `MISSION.md` goals. "For your blog API" not "for a generic app"
- **Graded difficulty** — start easy, increase. If user breezes through 3 in a row, jump difficulty. If stuck on 2 in a row, simplify or provide more scaffold
- **Save to workspace** — persist practice per [SKILL.md](../SKILL.md) "Workspace layout" (`concepts/<concept>/exercise.md` in the active topic workspace) so the user can revisit

## Exercise File Format

```markdown
# Exercise: {Title}

**Concept:** {What this practices}
**Difficulty:** {beginner | intermediate | advanced}
**Prerequisites:** {Glossary terms or prior learning records}

## Setup

{Context the user needs — code snippet, scenario description, relevant file paths}

## Task

{Clear instructions — what to do, what's expected}

## Hints (progressive)

1. {Orientation hint — restate the problem}
2. {Heuristic hint — guiding question}
3. {Pointing hint — where to look}

## Solution

{Full solution with explanation — reveal only after user attempts or requests}
```

## Codebase Mode Exercises

For repo-grounded exercises (grounding discovered per SKILL.md "Codebase mode"):

- Use ACTUAL repo code as setup material (Read the file, present the relevant section)
- Create exercises against real patterns the repo defines: "Add a new variant following the existing convention in {located file}"
- Reference real tests as examples of expected behavior
- Connect to the repo's own architectural rules: "Why would adding this dependency violate the repo's dependency-direction rule?"
