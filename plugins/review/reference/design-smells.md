# Design smells

The design-smell list the `code-reviewer` agent checks a diff against, and the catalog
`/review:setup` offers when a repository writes its own list. The `smell_baseline` setting
(`reference/config.md`) chooses which list the reviewer reads: `default` is the
[Baseline](#baseline) below, `off` is none, and a path is the repository's own file in the same
`- Name: sign → remedy` shape.

The names are the smells of Martin Fowler, *Refactoring* (2nd ed., 2018), chapter 3, "Bad Smells
in Code", whose 24 section headings the
[publisher's sample chapter](https://www.informit.com/articles/article.aspx?p=2952392) lists.
The signs and remedies are ours.

## Baseline

- Mysterious Name: understanding the name requires reading the body → pick a name that states the purpose
- Duplicated Code: one structure appearing more than once, boilerplate included at three or more sites → keep a single copy and call it
- Divergent Change: unrelated kinds of change all land in one module → separate the module by reason for change
- Shotgun Surgery: a single change needs small edits in many places → bring the pieces that change together into one place
- Feature Envy: a function works mostly on another module's data → relocate it beside that data
- Data Clumps: a group of values always passed side by side → give the group its own type
- Primitive Obsession: a domain idea carried as a raw string or number → wrap it in a small named type
- Repeated Switches: one branch on a kind value (a `kind` or `status` string) written out again in several modules, so a new kind means hunting down every copy → route every kind through a single dispatch point, or use polymorphism. It also covers a boolean that only ever mirrors another (`isReady` assigned wherever `isDraft` is cleared), fixed by replacing the pair with one enum or state field, and a diff that adds a kind by extending an `else if` chain already in place, fixed the same way as the copied branch
- Speculative Generality: abstractions, extension points or parameters with no current user → delete them until a second real caller exists
- Message Chains: callers walking `a.b().c().d()` through the object graph → let the first object hand over what the caller needs
- Middle Man: a type that mostly forwards to another → call the target directly
- Refused Bequest: a subtype ignoring or stubbing most of its inherited surface → prefer composition or a narrower interface

## Further candidates

The rest of chapter 3. The reviewer never reads this section; `/review:setup` offers it.

- Long Function: a function a reader cannot take in at once, often with comments marking its parts → extract each part into a named function
- Long Parameter List: more arguments than a caller can keep straight → pass an object that already holds them, or split the function
- Global Data: state any code can change from anywhere → put it behind one function that owns its reads and writes
- Mutable Data: a value changed in place where its readers do not expect it → narrow who can change it, or return a new value
- Loops: a hand-written loop doing what a pipeline of map, filter or reduce says directly → write the pipeline
- Lazy Element: a function or type that adds a name and nothing else → inline it
- Temporary Field: a field set only on some paths and empty the rest of the time → move it into its own type
- Insider Trading: two modules reading and writing each other's internals → move the shared part into one of them, or a third
- Large Class: a type holding many fields and responsibilities → split out the parts that change together
- Alternative Classes with Different Interfaces: two types doing the same job behind different method names → give them one interface
- Data Class: a type with fields and accessors but no behavior of its own → move the behavior that uses its fields onto it
- Comments: a comment explaining code that a better name or smaller function would make plain → change the code so the comment can go
