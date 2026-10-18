---
bump: patch
---

### Added

- `/testing:audit` flags two more C# constant oracles as `rule-inert-assertion`: MSTest `Assert.IsNotNull(typeof(X))` and `Assert.IsNotNull(nameof(X))`, and `Assert.Equal`, `NotEqual` and `Same` (`AreEqual`, `AreNotEqual` and `AreSame` in MSTest and NUnit) when both operands are `typeof(...)`. A runtime operand such as `obj.GetType()` stays unflagged.
