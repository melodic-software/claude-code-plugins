---
bump: minor
---

### Added

- **Two design-time defaults in `reference/design-principles.md`.** **Errors**: shape an operation
  so its ordinary cases cannot fail, and fail at once and visibly on a broken invariant or a
  defect. **Make illegal states unrepresentable**: model data so invalid combinations cannot be
  built.

### Changed

- **DIP** no longer says the high-level policy owns the abstraction; its cited source states no
  ownership.
- **Coupling and cohesion** is reworded to the definitions in Yourdon and Constantine's
  *Structured Design*, adds that dependencies between modules form no cycle, and cites that book
  and Martin's package principles in place of a profile page that carries no definition.
- **Information hiding** says that encapsulation is a means, and **Deep modules** says where
  unavoidable complexity goes (inside the module).
- **Reuse first** labels its ask-the-user clause as this plugin's own policy.
