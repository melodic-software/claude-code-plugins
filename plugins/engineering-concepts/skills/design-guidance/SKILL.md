---
description: "Loads the team's design positions into the session. Use before proposing or reviewing an architecture, a module layout, a library or service choice, an interface or abstraction and its names, or a call on duplicated code, or when asked for our design guidance."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Bring the team's design positions into the session
---

# Design guidance

Apply each position below to the design work in this session. When a position shapes a choice,
say which one and how; where you depart from one, say why.

1. **Duplication:** apply a rule of one, not the rule of three. Extract shared logic at the second
   copy, because a duplicate left until the third copy is much harder to clean up.
2. **Architecture styles:** always weigh event-driven architecture, a message bus, the monolith,
   and layered and clean architecture among the core styles when shaping a system, and combine
   them where each one helps.
3. **Vertical slices:** use vertical slice architecture as a lens to check each design item and
   split responsibilities. Share infrastructure such as the database context across slices
   instead of duplicating it; keep only slice logic separate.
4. **Abstraction names:** never carry a framework, vendor or underlying technology's name into an
   abstraction's name, because that makes the abstraction leaky.
5. **Dependencies:** adopt only official, trusted, actively maintained dependencies, each isolated
   behind an abstraction so it can be swapped without a cascade of changes.
6. **Defaults:** ship defaults that work out of the box with free tools and providers that need no
   key; keep paid options suggested and opt-in, never required.
