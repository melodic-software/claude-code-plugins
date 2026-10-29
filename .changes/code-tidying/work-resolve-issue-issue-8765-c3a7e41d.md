---
bump: minor
---

### Added

- `/code-tidying:audit-dead-code`: the grep lane now reads C# declarations ([#8765](https://github.com/melodic-software/claude-code-plugins/issues/8765)). It reads `.cs` files as text and runs no `dotnet`, MSBuild or other build, so the no-build rule from #5328 still holds. It reports two tier-2 shapes. `cs-unreferenced-private` covers a `private` member or type. `cs-unreferenced-symbol` covers any other type, and any other member whose line starts with an access modifier. Overrides, operators, constructors and indexers are not extracted. Either shape is reported when its name appears nowhere in the repository except where it is declared, every partial part and overload included. `.razor` and `.cshtml` views are part of that search, so a handler or parameter named in markup still counts as used. On the new trap fixtures, `cs-unreferenced-private` scored 66.7% precision and 66.7% recall, and `cs-unreferenced-symbol` scored 33.3% precision and 100% recall. A `.cs` file is no longer reported as `no lane for the language`. Its `unreferenced-file` stem drops every extension, so markup that spells `<Counter` saves `Counter.razor.cs`. The adjudication reference adds C# evidence patterns: reflection, assembly scanning, markup and serializers.
