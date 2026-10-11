# Type discipline

Read during Phase 3 (Type Modeling). Nothing in the rules depends on which statically typed language is in use. Idioms
for one language sit in that language's own file under `type-discipline/`, and Phase 3 opens such a
file only after detecting the language.

## Rules

**Where a shape comes from.** When another artifact already defines a shape (a schema, an API
description, a migration, a generated client), that artifact is the source: derive the type from
it, because a second copy written by hand drifts. Untyped data (request bodies, files, environment
variables, queue messages, database rows, replies from other services) is parsed once, at the point
it enters the program, into a domain type. The parse fails right there with an error naming the
input, and code beyond that point accepts the domain type without checking again what the parse
already established.

**What a value can hold.** Prefer a representation in which a bad value cannot be written down over
one that needs a check to stay correct. Money is a currency code plus a whole count of minor units,
not a float next to an unconstrained string; a page of results is its items together with either a
next-page cursor or an explicit marker saying it is the last. Distinct states each get their own
variant of a sum type (a tagged union, a sealed hierarchy, an enum with payloads), so a forbidden
state cannot be built at all. A request that is `idle`, `loading`, `loaded` with rows, or `failed`
with a reason is four variants. One record with an optional `rows`, an optional `error` and a status
string lets code build combinations nobody wants, since only comments say which ones are valid.
Strengthening stops once it stops paying: tighten a type only where some function would otherwise
fail, throw or return nothing for part of its input. When every function is total over the type it
takes, the model is strong enough, and wrapping values that no code ever confuses adds ceremony,
not safety.

**How code consumes a value.** Branch over a sum type in a form where a new variant breaks the build
at every site that ignores it; a catch-all default that silently swallows unknown variants hides the
sites the new one needs. The checker is never overruled: a cast, a non-null assertion or a
suppression comment asserting a type the code has not proven turns a compile-time error into a
run-time one. When the checker cannot see a fact, change the model or add the check that proves it.

## Language files

| Language | File | Loaded when |
|---|---|---|
| TypeScript | [`type-discipline/typescript.md`](type-discipline/typescript.md) | the repository has a `tsconfig.json`, or the change touches `.ts`, `.tsx`, `.mts` or `.cts` files |

A language with no file here uses the rules above with that language's own sum types, narrowing and
exhaustiveness check.
