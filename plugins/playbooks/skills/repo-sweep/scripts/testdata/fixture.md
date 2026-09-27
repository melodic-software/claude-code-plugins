# Playbook: fixture

## Phase 1: code

### dead-code

- skill: a:x
- args: .
- applies-when: repo has source code
- checked: true

### residue-dissolve

- skill: c:x, c:y
- args: .
- applies-when: repo has comments
- checked: true

### testing-audit

- skill: t:x
- args: .
- applies-when: repo has tests
- checked: true

### tidy

- skill: c:t
- args: <lane>
- applies-when: user wants a lane
- checked: false
- issue: #1

#### Override

Stay on the current branch.

## Phase 2: instructions

### prompt-audit

- skill: claude-api
- args: agent-instruction files
- applies-when: repo has agent instructions
- checked: true
