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

- **An `as` follows a check that proved it.** Inside a parse function, after the check, a cast to a
  brand is the one routine use. Anywhere else, change the model or narrow instead.
- **A type predicate (`value is T`) checks everything it claims.** A predicate that tests one field
  and claims the whole type is a cast with a reassuring name.
- **Narrowing, most preferred first:** a check on a literal tag field of a union; an `in` check;
  `typeof` or `instanceof`; a type predicate function; an `as` after validation.
- **Use `satisfies` to check a literal against a type** while keeping the literal's narrow inferred
  type. An annotation widens it to the declared type; `as` drops the assignability and
  excess-property checks an annotation would run, and rejects only types that do not overlap.

  ```ts
  const retry = { attempts: 3, backoff: "exponential" } satisfies RetryPolicy;
  ```

## Modeling

- **Unions with a literal tag** for variant state: `{ kind: "idle" } | { kind: "failed"; reason:
  string } | ...`.
- **Brands** for values that share a primitive but must not mix, such as two kinds of id. Only the
  parse function creates a branded value.

  ```ts
  declare const invoiceIdTag: unique symbol;
  type InvoiceId = string & { readonly [invoiceIdTag]: true };
  ```

- **Constructive types** where the shape can carry the rule: a tuple with a rest element
  (`[Line, ...Line[]]`) for "at least one", a union of string literals for a closed set. Move from
  `Line[]` to the tuple form when code reading the lines has to assert one exists: an index read
  followed by `!`, a cast, or a throw for the empty case. While every function over `Line[]` has an
  answer for zero lines, `Line[]` stays.
- **Exhaustiveness through `never`.** In the default branch of a switch over a tagged union, assign
  the value to a `never`-typed variable. A new variant then fails to compile at that switch.

  ```ts
  default: {
    const unhandled: never = state;
    return unhandled;
  }
  ```

- **Derive before declaring.** Indexed access types, `typeof`, and the utility types for picking,
  omitting, parameters, return types and awaited values build a type from the one that owns the
  shape. Declare a new interface only for a shape nothing else defines.

## Upstream record

- **Pointer:** TypeScript Handbook, [Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html)
  ("The `in` operator narrowing", "Using type predicates", "Exhaustiveness checking"), and the
  TypeScript 4.9 release notes, ["The `satisfies` Operator"](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-9.html).
- **As of:** 2026-10-04.
- **Recheck trigger:** a TypeScript major release, or either page changing how narrowing,
  exhaustiveness or `satisfies` behaves.
