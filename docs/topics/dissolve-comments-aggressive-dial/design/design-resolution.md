# Design resolution: dissolve-comments aggressive dial

outcome: early-exit
tier: B (light design)
reason: The change adds one posture value, two per-run argument tokens, and one flag to an existing
prose skill. No script, type, module, or package boundary changes; the skill's scripts are reused
as they are.

## Argument grammar sketch

```text
/code-tidying:dissolve-comments [safe] [aggressive | strip] [override] [--notes <path>] [target]
```

- Tokens are matched whole, in any order, and stripped before the target is read. `./aggressive`,
  `./strip`, `./safe`, and `./override` are paths.
- `--notes` consumes the next word as its path.
- `aggressive` and `strip` together: `strip` wins, since it is the narrower edit set (no rewrites).

## Effective mode resolution

| Inputs | Effective mode |
|---|---|
| `safe` token present | safe (whatever else is set) |
| non-interactive run on a widened rung | safe (whatever else is set) |
| `strip` token | strip |
| `aggressive` token | aggressive |
| no dial token, `comment_posture` = `aggressive` | aggressive |
| no dial token, `comment_posture` = `strict`, `balanced`, `conservative`, empty, or unknown | as today |

## What each mode applies

| Mode | Class A | Class B | Class C (non-exempt) | Exempt surfaces |
|---|---|---|---|---|
| strict (today) | delete, COMMENT-ONLY | per tier gate, else proposal | earn-its-keep test; failures deleted, over-budget rewritten | untouched |
| aggressive | delete, COMMENT-ONLY | per tier gate, else proposal and the comment stays | deleted with narrative staged, except a load-bearing warning, which is kept at `class_c_max_lines` | untouched |
| strip | delete, COMMENT-ONLY | deleted as a comment, no rewrite, COMMENT-ONLY, narrative staged | deleted, COMMENT-ONLY, narrative staged | untouched |
| safe | delete, COMMENT-ONLY | proposal | proposal | untouched |

Every applied deletion in every mode carries the COMMENT-ONLY proof; an UNPROVABLE file yields
proposals only.
