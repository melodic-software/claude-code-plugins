# Type discipline

Read during Phase 3 (Type Modeling). The rules hold in any statically typed language. Language
idioms live in one file per language under `type-discipline/`, and Phase 3 loads a file only when it
detects that language.

## Rules

1. **A forbidden state has no value.** Give each real state its own variant of a sum type (a tagged
   union, a sealed hierarchy, an enum with payloads). A record of optional fields whose valid
   combinations are written only in comments lets code build the combinations nobody wants. A
   request that is `idle`, `loading`, `loaded` with rows, or `failed` with a reason is four
   variants, not one record with an optional `rows`, an optional `error` and a status string.
2. **Build the value from parts that are always valid.** Choose a representation that cannot hold a
   bad value over one that needs a check to stay correct. An amount of money is a currency code
   plus a whole number of minor units, not a float beside a free string; a page of results is its
   items plus either a cursor to the next page or an explicit last-page marker.
3. **Parse outside input once, where it enters.** Request bodies, files, environment variables,
   queue messages, database rows and responses from other services arrive untyped. Convert each
   into a domain type at the point it crosses into the program, and fail there with an error that
   names the input. Code past that point takes the domain type and does not check the same facts
   again.
4. **The checker is never overruled.** A cast, a non-null assertion or a suppression comment that
   claims a type the code has not proven moves a compile error to run time. When the checker cannot
   see a fact, change the model or add the check that proves it.
5. **The compiler enforces exhaustive handling.** Branch over a sum type in a form where adding a
   variant fails the build at every site that does not handle it. A default branch that quietly
   absorbs unknown variants hides the sites a new variant needs.
6. **One source per shape.** When a schema, an API description, a migration or a generated client
   already defines a shape, derive the type from it. A hand-written second copy drifts.
7. **Strengthen only where a value can be wrong, then stop.** Tighten a type where a function
   would otherwise fail, throw or return nothing for some of its inputs. Once every function is
   total over the type it accepts, the model is strong enough. Wrapping values that no code mixes
   up adds ceremony and no safety.

## Language files

| Language | File | Loaded when |
|---|---|---|
| TypeScript | [`type-discipline/typescript.md`](type-discipline/typescript.md) | the repository has a `tsconfig.json`, or the change touches `.ts`, `.tsx`, `.mts` or `.cts` files |

A language with no file here uses the rules above with that language's own sum types, narrowing and
exhaustiveness check.
