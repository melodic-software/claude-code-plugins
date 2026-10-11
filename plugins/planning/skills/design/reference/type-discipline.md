# Type discipline

Read during Phase 3 (Type Modeling). Nothing in the rules depends on which statically typed language is in use. Idioms
for one language sit in that language's own file under `type-discipline/`, and Phase 3 opens such a
file only after detecting the language.

## Rules

Phase 3 meets each of these situations while it fills `type-inventory.md`. Find the row that
matches and make its decision.

| The design has | Decide | Reason |
|---|---|---|
| A shape that a schema, an API description, a migration or a generated client already defines | Derive the type from that artifact | Any hand-kept duplicate falls out of step with it |
| Data with no type yet: queue messages, request bodies, database rows, environment variables, files, replies from other services | Convert it into a domain type at its entry point, in a single parse that rejects bad input on the spot with an error naming that input | Everything downstream receives the domain type and trusts it, so nothing repeats the parse's checks |
| A value with limits on what it may hold | Pick the encoding that cannot express an invalid value ahead of one that relies on a check to remain valid. Money: a currency code with an integer count of minor units, never a float beside a free-form string. A page of results: its items with either a cursor for the next page or a marker saying this page is the last | A value that relies on a check stays valid only while every writer remembers the check |
| States that exclude one another | One variant per state in a sum type (a tagged union, a sealed hierarchy, an enum with payloads). A lane run has four: `queued`, `running`, `merged` carrying its PR number, and `failed` carrying a reason. A single record holding a status string beside an optional `prNumber` and an optional `failureReason` is the shape to avoid | That record compiles with a PR number and a failure reason set at once, and nothing but a comment says such a pair is invalid |
| A pull to tighten a type further | Add strength only at a function that, given the looser type, would throw, fail or have no result for some inputs. When every function returns a result for every value of the type it accepts, the model is strong enough | A wrapper around values no code mixes up costs ceremony and buys no safety |
| Code that branches over a sum type | Branch in a form that stops compiling at every site that leaves a newly added variant unhandled; no catch-all default that quietly absorbs variants it does not know | A catch-all conceals exactly the sites the new variant has to reach |
| A fact the checker cannot see | Change the model, or add the check that proves the fact. Never assert an unproven type with a cast, a non-null assertion or a suppression comment | Silencing the checker does not remove the error; it moves it from compile time to run time |

## Language files

| Language | File | Loaded when |
|---|---|---|
| TypeScript | [`type-discipline/typescript.md`](type-discipline/typescript.md) | the repository has a `tsconfig.json`, or the change touches `.ts`, `.tsx`, `.mts` or `.cts` files |

A language with no file here uses the rules above with that language's own sum types, narrowing and
exhaustiveness check.
