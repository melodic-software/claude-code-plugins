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

- **Ways to narrow, from last resort up to first choice:** an `as` after validation; a type
  predicate function; `typeof` or `instanceof`; an `in` check; a test of a union's literal tag field.
- **A type predicate (`value is T`) has to test all of `T`.** One that inspects a single field and
  then vouches for the whole type is still a cast, only with a name that sounds safe.
- **Every `as` sits after the check that justifies it.** Its one routine home is a parse function,
  casting to a brand once the check has passed. Everywhere else, narrow or change the model.

## Modeling

- **A new interface is only for a shape nothing else defines.** Otherwise build the type from the
  one that owns the shape: indexed access types, `typeof`, or the utility types for picking,
  omitting, parameters, return types and awaited values.
- **Variant state is a union with a literal tag**, such as `{ kind: "idle" } | { kind: "failed";
  reason: string } | ...`, and a switch over it closes with a `never` check. The default branch
  assigns the value to a `never`-typed variable, so a variant added later stops that switch from
  compiling.

  ```ts
  default: {
    const unhandled: never = state;
    return unhandled;
  }
  ```

- **Let the shape carry the rule where it can.** "At least one" is a tuple with a rest element
  (`[Line, ...Line[]]`), and a closed set is a union of string literals. `Line[]` stays for as long
  as every function over it has an answer for zero lines. Switch to the tuple once code reading the
  lines must assert that one exists, whether through an index read followed by `!`, a cast, or a
  throw for the empty case.
- **A brand separates values on one primitive that must never be swapped**, such as an invoice id
  and a customer id. Nothing but the parse function creates a branded value.

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
