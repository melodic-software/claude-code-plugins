# Simpler code over more code

When a unit of work can be written cleanly in fewer lines without sacrificing correctness, readability, test coverage, observability, or convention conformance, the smaller form is the default. Lines are liability: more to read, test, debug, refactor, and rename when conventions shift. This is a reasoning-only judgment: "simpler" is about intent and shape, not a character count a tool can enforce.

## Named failure modes to avoid

These are canonical smells, not invented ones:

- **Speculative generality**: hooks, parameters, and special cases for a "we might need this someday" requirement that never materializes. The tell: the only callers of a function or class are its own tests. ([Fowler, *Refactoring*](https://refactoring.guru/smells/speculative-generality))
- **The wrong abstraction**: an abstraction extracted before its shape is namable and stable (see `reference-dont-duplicate.md`, T4–T5). Duplication is cheaper than the wrong abstraction until then. Further reading: [Metz, *The Wrong Abstraction*](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction); [Dodds, AHA Programming](https://kentcdodds.com/blog/aha-programming).
- **YAGNI violation**: configurability, plugin points, or interfaces for requirements that do not exist yet.

## Constraints: never traded away for line count

Reducing code must not cost any of:

- **Clarity**: no single-letter names, no clever one-liners that hide intent, no suppressed type information.
- **Test coverage**: every behavior still has a test.
- **Error handling at boundaries**: resilience at system edges is not optional.
- **Established conventions**: dependency direction, naming, and layering hold.
- **Observability**: structured logs, traces, and metrics survive the cut.

## Reading the reduction

A reduction is **right** when it removes copy-paste duplication where the abstraction is namable and stable (see `reference-dont-duplicate.md`, T3–T5), collapses boilerplate into a helper, replaces a branch ladder with a lookup, uses a built-in framework primitive instead of a hand-rolled one, or deletes speculative parameters and code that only tests reference.

A reduction is **wrong** when it suppresses an analyzer rule, drops a test, disables a lint, hides intent behind cleverness, or forces one abstraction onto two cases that are not actually the same.

When in doubt, prefer the form that makes the next change cheaper.

## Build only what someone acts on

Before proposing anything new (code, a check, a process, a document, a configuration value, a dependency), name who uses its output and what they do with it. If nobody does, do not build it. When a problem has a removable cause, remove the cause rather than adding something that detects the problem or works around it. Between options that solve the same problem, count the moving parts and choose the one with the fewest.

## No bottleneck without a reason

Do not serialize work behind a single shared lock, a one-at-a-time queue, or a recurring manual step unless correctness or consent requires it: concurrent writes to the same state, or a person's go-ahead before a destructive change. Otherwise keep the shared thing safe by narrowing scope and protecting it, not by making it exclusive.

## Precedent is not a reason to keep something

An earlier answer, a design brief, or an existing pattern in the repository does not justify keeping a mechanism the evidence shows is unneeded. Say so, cite the evidence, and recommend removing it.
