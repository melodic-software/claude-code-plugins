# Zachman Framework 3.0 Quick Reference

The Zachman Framework is a 6x6 ontology for classifying enterprise architecture artifacts.

**Key insight:** TOGAF tells you *how* to create architecture. Zachman tells you *how to organize* what you create.

## The Matrix

### Columns (Interrogatives)

Each column answers a fundamental question:

| # | Column | Interrogative | Focus |
| --- | --- | --- | --- |
| 1 | What | Data | Things of interest, entities |
| 2 | How | Function | Processes, transformations |
| 3 | Where | Network | Locations, distribution |
| 4 | Who | People | Roles, responsibilities |
| 5 | When | Time | Events, schedules, cycles |
| 6 | Why | Motivation | Goals, strategies, rules |

### Rows (Perspectives)

Each row represents a stakeholder level with increasing detail:

| # | Row | Perspective | Audience | Level |
| --- | --- | --- | --- | --- |
| 1 | Planner | Executive | Board, C-suite | Scope/Context |
| 2 | Owner | Business | Business managers | Business Model |
| 3 | Designer | Architect | Solution architects | Logical Design |
| 4 | Builder | Engineer | Developers | Physical Design |
| 5 | Subcontractor | Technician | Implementers | Detailed Specs |
| 6 | User | Operations | End users, operators | Running System |

## The Full Matrix

```text
         │ What      │ How       │ Where     │ Who       │ When      │ Why
         │ (Data)    │ (Function)│ (Network) │ (People)  │ (Time)    │ (Motivation)
─────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────
Planner  │ Business  │ Business  │ Business  │ Business  │ Business  │ Business
(Scope)  │ Entities  │ Processes │ Locations │ Roles     │ Cycles    │ Goals
─────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────
Owner    │ Semantic  │ Business  │ Logistics │ Work Flow │ Master    │ Business
(Business)│ Model    │ Process   │ Network   │ Model     │ Schedule  │ Plan
─────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────
Designer │ Logical   │ System    │ Distributed│ Human    │ Processing│ Business
(Logical)│ Data Model│ Design    │ System    │ Interface │ Structure │ Rules
─────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────
Builder  │ Physical  │ Technology│ Technology│ Presenta- │ Control   │ Rule
(Physical)│ Data Model│ Design   │ Architecture│ tion    │ Structure │ Specification
─────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────
Subcontr │ Data      │ Detailed  │ Network   │ Security  │ Timing    │ Rule
(Detail) │ Definition│ Program   │ Architecture│ Architecture│ Definition│ Design
─────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────
User     │ Operational│ Operational│ Operational│ Operational│ Operational│ Operational
(Running)│ Data      │ Functions │ Network   │ Organization│ Schedule │ Strategy
```

## Cell Examples

### Row 4 (Builder) - Code Extractable

```text
| Column | Question | What You Find in Code |
| --- | --- | --- |
| What | What data structures? | Models, schemas, types |
| How | How is it built? | Algorithms, patterns |
| Where | Where does it run? | Deployment configs |
| Who | Who maintains it? | Git history, CODEOWNERS |
| When | When does it execute? | Schedulers, triggers |
| Why | Why this approach? | ADRs, comments |
```

### Row 1 (Planner) - Requires Human Input

```text
| Column | Question | Where to Find |
|--------|----------|---------------|
| What | What are business entities? | Business glossary |
| How | What are core processes? | Process documentation |
| Where | Where do we operate? | Business geography |
| Who | What is the org structure? | Org chart |
| When | What are business cycles? | Business calendar |
| Why | What are strategic goals? | Strategy documents |
```

## Using the Framework

### For Coverage Checking

Use as a checklist to ensure documentation completeness:

```text
         What  How   Where  Who   When  Why
Planner   [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
Owner     [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
Designer  [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
Builder   [x]   [x]   [x]   [ ]   [ ]   [x]  ← ADRs
Subcontr  [x]   [x]   [x]   [ ]   [ ]   [ ]
User      [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
```

### Minimum Viable Coverage

For most projects, ensure at least:

- Row 3, Column 1-2 (Designer: What & How) - Architecture diagrams
- Row 4, Column 1-2 (Builder: What & How) - Technical specs
- Row 4, Column 6 (Builder: Why) - ADRs

### Comprehensive Coverage

For enterprise-scale work:

- All cells for rows 3-5
- Key cells for rows 1-2 (with stakeholder input)

## Wizard Mode

If unsure which row/column to use:

**Step 1: Who's the audience?**

- Executives → Row 1 (Planner)
- Business managers → Row 2 (Owner)
- Architects → Row 3 (Designer)
- Developers → Row 4 (Builder)
- Implementers → Row 5 (Subcontractor)
- Operations → Row 6 (User)

**Step 2: What question?**

- About data/things → Column 1 (What)
- About processes → Column 2 (How)
- About locations → Column 3 (Where)
- About people/roles → Column 4 (Who)
- About timing/events → Column 5 (When)
- About goals/rules → Column 6 (Why)

## Related Resources

- zachman-analysis skill for detailed analysis
- zachman-limitations.md for code extraction limits
- `/ea:zachman-analyze` command for perspective analysis

---

**Last Updated:** 2025-12-05
