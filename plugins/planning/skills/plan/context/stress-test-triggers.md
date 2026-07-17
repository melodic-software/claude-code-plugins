# Stress-Test Trigger Criteria

When to invoke `/devils-advocate` on a plan. The goal is to catch plans that carry enough risk to warrant systematic adversarial review — without stress-testing every trivial change.

## Always stress-test when ANY of these match

- **Infrastructure changes** — hooks, CI/CD workflows, build configuration, deployment scripts, MCP server config. These affect every session or every build
- **Architecture decisions affecting multiple projects** — new shared libraries, dependency direction changes, layer boundary modifications
- **Cross-cutting concerns** — logging, error handling, observability, authentication. Changes propagate across the codebase
- **New conventions or enforcement mechanisms** — new analyzer/lint rules, new hooks, new agent-instruction rules. These constrain all future work
- **Multi-step implementations with 3+ steps** that touch undocumented or poorly-understood behavior. The failure surface area grows with step count
- **External dependency changes** — adding, removing, or upgrading third-party packages. Especially when the package interacts with other dependencies
- **Security-sensitive changes** — auth, tokens, secrets, permissions, network boundaries
- **Breaking changes** — anything that changes a public API, removes a feature, or modifies behavior that other code depends on

## Never stress-test (research validation is sufficient)

- **Single-file documentation updates** — unless the doc drives enforcement (e.g., agent-instruction rules)
- **Trivial code fixes** — typos, formatting, comment updates
- **Test-only changes** — adding or fixing tests without changing production code
- **Config tweaks with well-understood behavior** — editor-config severity changes, gitignore patterns

## Gray area — use judgment

- **2-3 file changes with clear scope** — if the files are independent, skip. If they interact, stress-test
- **New skill creation** — stress-test if the skill composes other skills or has side effects. Skip for simple reference skills
- **Refactoring without behavior change** — usually skip, unless the refactoring changes module boundaries

## How to assess blast radius

Ask these questions:

1. **How many files/projects are affected?** — 1-2: LOW, 3-10: MEDIUM, 10+: HIGH
2. **Are other developers/sessions affected?** — shared config, hooks, CI: HIGH
3. **Is it reversible?** — git revert works: LOWER. Database migration, published API: HIGHER
4. **Are there automated checks?** — analyzer rules, architecture tests, CI gates reduce risk
5. **Does it touch undocumented behavior?** — if yes, stress-test regardless of scope

Combine into: LOW / MEDIUM / HIGH / CRITICAL

## Domain-specialist skills for stress-testing

When a stress-test trigger touches a domain with a dedicated installed skill or plugin (cloud deployment, AI/ML, edge compute, MCP design), cite that skill's slash invocation for deeper analysis — see [plan-template.md](plan-template.md) "Domain-specialist skills during planning".
