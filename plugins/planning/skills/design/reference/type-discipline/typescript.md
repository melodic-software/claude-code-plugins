# Type discipline: TypeScript

Read during Phase 3 when the repository has a `tsconfig.json` or the change touches `.ts`, `.tsx`,
`.mts` or `.cts` files. It applies the rules in [`../type-discipline.md`](../type-discipline.md) to
TypeScript; read that file first.

## Outside input

- **Type it `unknown`, never `any`.** `unknown` forces a check before use; `any` turns the checker
  off for everything the value touches.
- **Parse with the schema library the repository already declares.** Look in `package.json`
  (`dependencies` and `devDependencies`) and in existing code for a runtime schema library. When
  one is there, write a schema for each boundary type, parse with it, and take the TypeScript type
  from the library's own type-inference helper, so the schema is the one source of the shape. No
  library is the default: use the one the manifest names.
- **When the type is written first, make the schema prove it.** A type that exists before its
  schema (a shared contract, a generated type) gets a schema declared with the library's
  schema type parameterized by that type. A schema that accepts less than the type then fails to
  compile, instead of drifting. In the sketch below, `SchemaOf` stands for that library type.

  ```ts
  type Invoice = { id: InvoiceId; total: Money; dueOn: string };

  // Dropping `dueOn` from the schema is now a compile error.
  const invoiceSchema: SchemaOf<Invoice> = /* the library's object schema for Invoice */;
  ```

- **No schema library declared: write a parse function, add no dependency.** It takes `unknown`
  and returns either the domain type or a failure that names the bad field. Adding a library is a
  design thread of its own, never a side effect of one boundary.

  ```ts
  type Parsed<T> = { ok: true; value: T } | { ok: false; error: string };

  function parseInvoice(raw: unknown): Parsed<Invoice> {
    if (raw === null || typeof raw !== "object") {
      return { ok: false, error: "invoice: expected an object" };
    }
    if (!("id" in raw) || typeof raw.id !== "string" || raw.id === "") {
      return { ok: false, error: "invoice.id: expected a non-empty string" };
    }
    // ...one check per field, then build the domain value
  }
  ```

- **The parse result has a domain name.** The parse returns `Invoice`, not
  `Record<string, unknown>` or an inline object type. Nothing past the boundary handles the loose
  shape.

## Casts and narrowing

- **To hold a literal to a type, write `satisfies`.** The literal is checked against `RetryPolicy`
  and keeps the narrow type TypeScript inferred for it. An annotation would widen the value to the
  declared type instead, and `as` skips the assignability and excess-property checks an annotation
  runs, refusing only a type that shares nothing with the value.

  ```ts
  const retry = { attempts: 3, backoff: "exponential" } satisfies RetryPolicy;
  ```

- **Narrow with a check the compiler runs; write a claim only where none can.** A type predicate
  and an `as` are claims: the compiler takes your word for them. This repository's context-guard
  hooks show where each one belongs, in the order a value meets them:

  | Where the value is | What this repository does | Kind |
  |---|---|---|
  | Just arrived as `unknown` and no compiler check settles it | `isZone(word: unknown): word is Zone` tests the word against the closed `ZONES` list (`plugins/context-guard/hooks/zone.ts`) | claim |
  | Data a validation step has already checked | `asRule` casts `v.action as Action` only after `ACTIONS.includes(...)` passed (`plugins/context-guard/hooks/register.tsx`) | claim |
  | A union whose members carry a literal tag | `e.kind === 'crossing'` picks the crossing events out of the event list (`register.tsx`) | compiler check |
  | An object whose possible shapes differ in which keys they have | A key test such as `'raw' in v` narrows only when `v` is declared as a union of those shapes. After a cast to `Record<string, unknown>`, as in `plugins/context-guard/hooks/zone.test.ts`, it narrows nothing, so declare the union first | compiler check, on a union only |
  | A caught error, another class instance, or a primitive | `error instanceof Error ? error.message : String(error)` (`register.tsx`) | compiler check |

  When more than one compiler check fits, use the most specific: a tag names the member outright,
  a key test infers it from one key, and `typeof` or `instanceof` sorts only by runtime kind.
  Of the two claims, write a predicate before an `as`.

- **A predicate is a claim only its author checks.** `function isManifest(v): v is PluginManifest`
  that reads `name` and skips `version` lets a manifest with no version through as a
  `PluginManifest`, and the compiler trusts it. The body tests every field the return type names.
- **In a parse function, once the check has passed, `as` turns the checked string into its brand.**
  That is the cast's one routine use, and it always follows the check that justifies it. Anywhere
  else, narrow instead, or change the model so no cast is needed.

## Modeling

- **A shape some code already holds is computed from that code.** A hand-written copy drifts from
  its owner. A new interface is right only for a shape no type, function or constant defines yet.

  | You need | Compute it as |
  |---|---|
  | What a function returns | `ReturnType<typeof parseInvoice>`, wrapped in `Awaited<...>` when it returns a promise |
  | One field of a type | `Invoice["total"]` |
  | The shape of a constant | `typeof retry` |
  | What a function takes | `Parameters<typeof parseInvoice>` |
  | A type minus some fields, or only some of them | `Omit<Invoice, "id">`, `Pick<Invoice, "id" \| "dueOn">` |

- **Variant state is a union with a literal tag**, such as `{ kind: "idle" } | { kind: "failed";
  reason: string } | ...`. End every switch over it with a default branch that hands the value to a
  variable declared `never`. While each variant has its case, the value there is `never` and the
  assignment compiles; once a variant arrives without a case it no longer is, and the build fails
  at that switch.

  ```ts
  default: {
    const unhandled: never = state;
    return unhandled;
  }
  ```

- **Let the shape carry the rule where it can.** A closed set is a union of string literals, and
  "at least one" is a tuple with a rest element, `[Phase, ...Phase[]]`. To choose between `Phase[]`
  and that tuple, read the code that consumes the list. Where an empty list is a normal case the
  consumer has a branch for, the plain array stays: `showCrossing` in
  `plugins/context-guard/hooks/register.tsx` takes `due.at(-1)` and tests it against `undefined`
  before using it, so `Crossing[]` is the right type there. Where the consumer has no such branch
  and still needs a first element, the guarantee lives only in the author's head; move it into the
  tuple type so the compiler enforces it.
- **Brand two kinds of value that share a primitive and must never be swapped.** An invoice id and
  a customer id are both strings; with a brand on each, passing one where the other belongs fails
  to compile. Only the parse function produces a branded value.

  ```ts
  declare const invoiceIdTag: unique symbol;
  type InvoiceId = string & { readonly [invoiceIdTag]: true };
  ```

## Upstream record

- **Pointer:** TypeScript Handbook, [Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html)
  ("The `in` operator narrowing", "Using type predicates", "Exhaustiveness checking"), and the
  TypeScript 4.9 release notes, ["The `satisfies` Operator"](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-9.html).
- **As of:** 2026-10-04.
- **Recheck trigger:** a TypeScript major release, or either page changing how narrowing,
  exhaustiveness or `satisfies` behaves.
