---
topic: js-adapter-contract-design
section: enforcement-lanes
abstract: "Runtime duck-typing, JSDoc+checkJs, and a shared conformance suite catch disjoint defect classes; only the suite catches a wrong-behaviour adapter, and this repo's type lane is switched off."
claims:
  - claim: "An object literal annotated @type/@satisfies errors on a missing required method (TS2741/TS1360) and on an excess property, but a method declared with FEWER parameters than the typedef is accepted silently."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://www.typescriptlang.org/docs/handbook/type-checking-javascript-files.html"
        tier: 1
        pool: "Microsoft/TypeScript"
      - url: "local probe: TypeScript 6.0.3 (repo-pinned), scratch project mirroring extraction/tsconfig.json"
        tier: 0
        pool: "first-party empirical (this machine)"
  - claim: "A runtime-interpolated dynamic import resolves to `any`, which also disables checking of the HOST's use of the adapter; an enumerated static registry restores it, including with lazy `() => import()` thunks."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://www.typescriptlang.org/docs/handbook/modules/reference.html"
        tier: 1
        pool: "Microsoft/TypeScript"
      - url: "local probe: TS 7.0.2 registry/thunk annotation, TS2322 + TS2741 reproduced"
        tier: 0
        pool: "first-party empirical (this machine)"
  - claim: "SQLAlchemy's dialect conformance suite is consumed by `from sqlalchemy.testing.suite import *`, with non-support declared out-of-band via a pointed-at requirements class (79 exclusions.open vs 112 exclusions.closed, no global default)."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://raw.githubusercontent.com/sqlalchemy/sqlalchemy/main/README.dialects.rst"
        tier: 1
        pool: "SQLAlchemy"
      - url: "https://raw.githubusercontent.com/snowflakedb/snowflake-sqlalchemy/main/tests/sqlalchemy_test_suite/test_suite.py"
        tier: 1
        pool: "Snowflake (independent third-party dialect)"
  - claim: "Vitest has no RSpec-style shared_examples; the idiomatic shape is a non-.test.js module exporting a function that calls describe/it, imported by each adapter's own test file."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://vitest.dev/api/"
        tier: 1
        pool: "Vitest"
      - url: "local probe: vitest 4.1.10, per-file attribution and it.skipIf verified"
        tier: 0
        pool: "first-party empirical (this machine)"
  - claim: "Of five mature JS plugin hosts, only PostCSS validates plugin shape eagerly at load; ESLint validates at lint time, Rollup/Vite never validate, Fastify defers to ready()."
    confidence: MEDIUM
    tiers: [1]
    sources:
      - url: "https://raw.githubusercontent.com/postcss/postcss/main/lib/processor.js"
        tier: 1
        pool: "PostCSS"
      - url: "https://raw.githubusercontent.com/eslint/eslint/v9.0.0/lib/linter/linter.js"
        tier: 1
        pool: "ESLint"
produced_by: lane-a
---

# (a) Enforcement lanes for a JS adapter/plugin contract

Scope: plain ESM JavaScript, no TypeScript source, no classes, JSDoc types, vitest, Node 24.

**Empirical provenance.** Every claim marked *(probe)* was produced by running the tool on this
machine, not read from documentation. Pins: **Node v24.18.0**, **TypeScript 7.0.2** (`npx -y
typescript@7.0.2`), **vitest 4.1.10**. Probe sources live under the session scratchpad
(`scratchpad/tsprobe*`, `scratchpad/vitestprobe`) and are disposable. A second TypeScript major was
not run, so TS-version stability of the empirical results rests on the documented rules quoted
alongside them.

Confidence markers: **VERIFIED** (official doc quote and/or reproduced locally) / **UNVERIFIED** /
**REFUTED**.

---

## Executive answer

Three lanes, ordered by *when* a defect surfaces and *to whom*:

| Lane | Defect surfaces | To whom | Catches |
|---|---|---|---|
| 1. TS checking of JSDoc | CI / editor, before merge | adapter author | wrong *shape* — missing member, wrong declared types, typo'd key |
| 2. Runtime load-boundary check | process start / plugin registration | host operator | *this specific module isn't an adapter*, attributably |
| 3. Shared conformance suite | CI, per adapter | adapter author | wrong *value* and wrong *behaviour* — the only lane that does |

Lane 3 is the only one that catches "the adapter produced the wrong thing." Lanes 1 and 2 both
check shape; they differ only in *when* and *whether the module was visible at all*.

---

## LANE 1 — TypeScript's JS-checking of JSDoc

### 1. `// @ts-check`, `// @ts-nocheck`, and the `allowJs` interaction

**`// @ts-check` enables checking in a project with `checkJs: false`.** VERIFIED — doc and probe.

Official sentence, `checkJs` option reference (<https://www.typescriptlang.org/tsconfig/#checkJs>):

> When `checkJs` is enabled, errors will be reported in JavaScript files. This is equivalent to
> prefixing `// @ts-check` to each file which is included in your project.
>
> You can ignore errors in JavaScript files by adding a `// @ts-nocheck` comment to the files.
> Conversely, you can choose a few files to be checked with `// @ts-check` by setting `checkJs` to
> `false` and only enabling it for some files.

Probe (`tsprobe4`), three configs over the same three files:

| config | `checked.js` (`// @ts-check`) | `unchecked.js` (no directive) | `nocheck.js` (`// @ts-nocheck`) |
|---|---|---|---|
| `allowJs:true, checkJs:false` | **TS2322 error** | silent | silent |
| `allowJs:true, checkJs:true` | **TS2322 error** | **TS2322 error** | silent |
| `allowJs:false` | *file not in program* | *file not in program* | *file not in program* |

So: `// @ts-check` opts a single file **in** under `checkJs:false`; `// @ts-nocheck` opts a single
file **out** under `checkJs:true`. Both VERIFIED (probe).

**Exact `allowJs` interaction — this is the one that traps people.** `allowJs:false` does not merely
disable checking; the `.js` files are **not in the program at all**. The probe emitted:

```
error TS18003: No inputs were found in config file 'tsconfig.allowjs-false.json'.
Specified 'include' paths were '["checked.js","unchecked.js","nocheck.js"]' and 'exclude' paths were '[]'.
```

VERIFIED (probe). `// @ts-check` cannot rescue a file `allowJs` excludes — the directive is inert
because the compiler never reads the file. **`allowJs` is the gate; `checkJs` is the default; the
per-file directives are the override.** `allowJs` doc: "Allows JavaScript files to be imported
inside your project, instead of just allowing them to be a part of the project."
(<https://www.typescriptlang.org/tsconfig/#allowJs>) VERIFIED.

**Hole worth naming:** `// @ts-nocheck` is a one-line, silent, universal opt-out of the entire type
lane, available to any adapter author. It *is* closable by lint: `@typescript-eslint/ban-ts-comment`
defaults to `'ts-nocheck': true` (i.e. flagged) in its recommended configuration
(<https://typescript-eslint.io/rules/ban-ts-comment/>) VERIFIED. If Lane 1 is load-bearing for
adapters you do not author, that lint rule is not optional.

### 2. `@satisfies` in JSDoc

**Syntax:** `/** @satisfies {SomeType} */` on a declaration, or inline on a parenthesized
expression: `/** @satisfies {ConfigOptions} */ ({ ... })`. VERIFIED — TS 5.0 release notes
(<https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-0.html>).

**Version: TypeScript 5.0** for the JSDoc tag; the underlying `satisfies` *operator* landed in
**TypeScript 4.9**. VERIFIED — TS 5.0 release notes:

> TypeScript 4.9 introduced the `satisfies` operator. It made sure that the type of an expression
> was compatible, without affecting the type itself. […] That's why TypeScript 5.0 is supporting a
> new JSDoc tag called `@satisfies` that does exactly the same thing.

JSDoc Reference entry (<https://www.typescriptlang.org/docs/handbook/jsdoc-supported-types.html>):
"Satisfies is used to declare that a value implements a type but does not affect the type of the
value." VERIFIED.

**Scope note:** `@satisfies` is an *expression-level* conformance check, not an object-literal
feature. The JSDoc Reference's own example applies it to a string literal —
`/** @satisfies {WelcomeMessage} */ const message = "hello world"  // const message: "hello world"` —
VERIFIED. The probes below exercise object literals because that is the adapter case, not because
the tag is restricted to them.

**How it differs from `@type` for an object literal.** `@type` is an annotation: it supplies a
contextual type and the declared variable **takes that type**, widening/erasing the literal's more
specific inferred member types. `@satisfies` checks conformance and **discards the constraint**,
leaving the inferred type. TS 4.9 release notes state the motivation
(<https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-9.html>):

> we want to ensure that some expression *matches* some type, but also want to keep the *most
> specific* type of that expression for inference purposes […] The new `satisfies` operator lets us
> validate that the type of an expression matches some type, without changing the resulting type of
> that expression.

Probe (`tsprobe3/satisfies2.js`), using the release notes' own `Palette = Record<'red'|'green'|'blue',
string | RGB>` shape:

| expression | result |
|---|---|
| `viaType.green.toUpperCase()` where `viaType` is `@type {Palette}` | **TS2339** `Property 'toUpperCase' does not exist on type 'string \| RGB'` |
| `viaSatisfies.green.toUpperCase()` where `viaSatisfies` is `@satisfies {Palette}` | **no error** |
| `@satisfies {Palette}` on `{ red, green, bleu }` | **TS2353** `'bleu' does not exist in type 'Palette'` |

VERIFIED (probe). So: `@type` widens (`green` becomes `string | RGB`); `@satisfies` preserves
(`green` stays `string`); both still catch the typo.

**`@satisfies` also catches missing and wrong members** — verified separately because it is
load-bearing for the recommendation in §4. Probe (`tsprobe3/satisfies3.js`):

```
satisfies3.js(10,6): error TS2739: Type '{ name: string; }' is missing the following
                     properties from type 'Adapter': fetchOne, fetchMany
satisfies3.js(16,3): error TS2322: Type 'number' is not assignable to type 'string'.
```

VERIFIED (probe). `@satisfies` is a full assignability check plus excess-property check, minus the
widening.

### 3. What the JSDoc lane does NOT catch

#### 3(i) Object literal annotated `@type {SomeInterface}`

Probe (`tsprobe1`), typedef `Adapter { name, fetchOne(url, opts), fetchMany(ids), supports? }`:

| case | result | verdict |
|---|---|---|
| **missing** required method | `TS2741: Property 'fetchMany' is missing in type '{...}' but required in type 'Adapter'` | **caught** VERIFIED |
| **extra** method on a fresh literal | `TS2353: Object literal may only specify known properties, and 'bogusExtra' does not exist in type 'Adapter'` | **caught** VERIFIED |
| **wrong parameter type** | `TS2322 … Types of parameters 'url' and 'url' are incompatible. Type 'string' is not assignable to type 'number'.` | **caught** VERIFIED |
| **fewer parameters** than declared | *no error at all* | **NOT caught** VERIFIED — see §6 |
| **more parameters** than declared | `TS2322 … Target signature provides too few arguments. Expected 3 or more, but got 2.` | **caught** VERIFIED |

**Important qualifier on "extra method".** The excess-property check is a *fresh object literal*
check only. Probe (`tsprobe2/indirect.js`): building the object into a `const` first and then
assigning it to the annotated binding — and likewise returning it from a function annotated
`@returns {Adapter}` — produced **no error** for the same stray `bogusExtra` member. VERIFIED
(probe). So "does it error on an EXTRA method?" is **only if the object is written inline at the
annotated position**. Any indirection defeats it. This matters because real adapters are frequently
assembled (spread, factory, conditional composition) rather than written as one literal.

#### 3(ii) Runtime behaviour and return *value* shape

**Nothing.** The type lane checks *declared* types only. It cannot observe that `fetchOne` resolves
`{ok:false}` rather than rejecting, that a returned array has one entry per input id, that an error
is signalled as a failure `Result` rather than a thrown exception, or that an optional method's
absence triggers the documented fallback. A `Promise<{ok: boolean, body: string}>` return annotation
is satisfied identically by an adapter that fulfils correctly and one that rejects — the rejection
path is simply not in the type. VERIFIED by construction and demonstrated in Lane 3 below, where a
structurally perfect adapter fails the behavioural suite.

#### 3(iii) Dynamic `import()` with a runtime-interpolated path — **can tsc see it at all?**

**No. The resolved module is typed `any`.** VERIFIED (probe, `tsprobe2/dynimport.js`). The probe
assigned each resolved module to `/** @type {never} */` to force the compiler to print the inferred
type:

```
dynimport.js(8,9):  error TS2322: Type 'any' is not assignable to type 'never'.
dynimport.js(15,9): error TS2322: Type '{ default: typeof import(".../contract"); }'
                    is not assignable to type 'never'.
```

Line 8 is `await import(\`./adapters/${name}.js\`)` — **`any`**. Line 15 is `await
import('./contract.js')` with a fully static specifier — a **real module type**. The contrast is the
whole answer.

The consequence is not neutral, it is actively corrosive: `any` silently accepts everything. The
probe's third function,

```js
const mod = await import(`./adapters/${name}.js`);
return mod.thisMethodDoesNotExist(1, 2, 3).andNeitherDoesThis;
```

produced **zero errors**. VERIFIED (probe). So for a runtime-interpolated plugin path the type lane
does not merely fail to check the adapter — it stops checking the *host's own consumption* of it too.

### 4. Is there a JSDoc equivalent of `implements`?

**There is an `@implements` tag, but it is class-only, so it does not apply to a plain object.**
VERIFIED — JSDoc Reference
(<https://www.typescriptlang.org/docs/handbook/jsdoc-supported-types.html>) documents `@implements`
under **Classes**, alongside `@extends`, `@public`/`@private`/`@protected`, `@override`, `@class`,
`@this`:

> In the same way, there is no JavaScript syntax for implementing a TypeScript interface. The
> `@implements` tag works just like in TypeScript:
> ```js
> /** @implements {Print} */
> class TextBook {
>   print() { }
> }
> ```

Since the brief excludes classes, `@implements` is unavailable. (Note also `@readonly` is listed in
the same Classes group and documented for instance properties — "ensures that a property is only
ever written to during initialization" — not as a `@property` member modifier inside a `@typedef`.)

**Recommended idiom for "this plain object conforms to this typedef":**

1. **`/** @satisfies {import('./contract.js').Adapter} */` on the exported object — RECOMMENDED.**
   It performs the full conformance check (missing member → TS2739, wrong type → TS2322, typo →
   TS2353, all VERIFIED by probe) *and* preserves the concrete inferred type, so the module's own
   consumers still see the precise shape, and capability flags stay literal-typed rather than
   widening to `boolean`/`string`.
2. `/** @type {import('./contract.js').Adapter} */` — equally good at catching errors, but widens
   the export to the interface. Choose it deliberately when you *want* the export opaque.
3. There is no third option that reads as `implements` without a class.

The `import('./contract.js').Adapter` form inside the annotation is the right way to reference a
typedef across module boundaries and needs no runtime import. VERIFIED (used throughout the probes,
all resolved).

**Caveat that applies to both #1 and #2:** neither closes the arity hole (§6), and #2's excess-member
detection evaporates under indirection (§3(i)).

### 5. JSDoc typedefs vs `.d.ts` for expressing a contract

| feature | JSDoc | evidence |
|---|---|---|
| **generics** | supported via `@template`, incl. constraints and defaults (`@template [T=object]`) | VERIFIED — JSDoc Reference; probe `tsprobe5`: `Box<number>` resolved, `{ value: 'nope' }` → TS2322, and the `set` callback param was contextually typed |
| **overloads** | supported via `@overload` (**TS 5.0**) | VERIFIED — probe `tsprobe5/expressive.js`: `ident('a')` OK, `ident(1)` assigned to `string` → TS2322. Version per TS 5.0 release notes (<https://devblogs.microsoft.com/typescript/announcing-typescript-5-0/>). **Doc gap:** `@overload` is *not listed* on the JSDoc Reference page despite working — do not rely on that page as the tag inventory |
| **optional properties** | supported, two syntaxes: `@property {number=} p` (Closure) and `@prop {number} [p]` (JSDoc), with defaults `[p=42]` | VERIFIED — JSDoc Reference |
| **readonly members** | **no `@property`-level modifier.** `@readonly` is class-instance-property scoped. Workaround: a utility type in the type expression | VERIFIED — probe `tsprobe5`: `@typedef {Readonly<{a: string, b: number}>} FrozenPair` then `f.a = 'y'` → `TS2540: Cannot assign to 'a' because it is a read-only property` |

**Practical frictions beyond the feature matrix:**

- **Silent phantom type parameters.** During probing, prose containing the literal text `@template`
  mid-sentence inside a `@typedef` comment was parsed as a second type-parameter declaration,
  yielding `TS2314: Generic type 'Box' requires 2 type argument(s)` with no indication of the cause.
  VERIFIED (probe, reproduced and then fixed). JSDoc has no syntax error — malformed tags degrade
  silently into wrong types. A `.d.ts` would have been a parse error.
- **Variance is *stricter* in JSDoc, not looser** — see §6.

### 6. Parameter arity and variance — **the real hole**

#### Fewer parameters ARE assignable

**VERIFIED both ways.** Documented rule, handbook "Type Compatibility" → *Comparing two functions*
(<https://www.typescriptlang.org/docs/handbook/type-compatibility.html>):

> You may be wondering why we allow "discarding" parameters like in the example `y = x`. The reason
> for this assignment to be allowed is that ignoring extra function parameters is actually quite
> common in JavaScript. For example, `Array#forEach` provides three parameters to the callback
> function: the array element, its index, and the containing array. Nevertheless, it's very useful
> to provide a callback that only uses the first parameter.

Probe (`tsprobe1/fewer.js`) — an adapter whose methods take **zero** parameters against a typedef
declaring two:

```js
/** @type {import('./contract.js').Adapter} */
export const a = {
  name: 'x',
  fetchOne: async () => ({ ok: true, body: '' }),   // typedef: (url: string, opts: {timeout:number})
  fetchMany: async () => [],                        // typedef: (ids: string[])
};
```

**Zero errors.** VERIFIED (probe). The same is true under `@satisfies` (probe
`tsprobe3/satisfies3.js`, `fewerParams` — no error).

**Why this matters for contract conformance specifically.** The rule is correct and desirable for
*callbacks* (the `forEach` case the handbook cites). It is exactly wrong for *adapters*, where the
declared parameters are the contract's inputs. An adapter that ignores the `opts` argument — and so
silently ignores `timeout` — type-checks perfectly. An adapter that ignores `ids` and returns a
constant type-checks perfectly. This is a **behavioural** defect wearing a valid type, and only Lane
3 catches it. The asymmetry is complete: too *many* parameters is an error (`TS2322 … Target
signature provides too few arguments`), too *few* is silent.

#### Method-vs-property declaration variance

**`strictFunctionTypes` does not apply to method-shorthand declarations.** VERIFIED — official
`strictFunctionTypes` reference (<https://www.typescriptlang.org/tsconfig/#strictFunctionTypes>):

> During development of this feature, we discovered a large number of inherently unsafe class
> hierarchies, including some in the DOM. Because of this, the setting only applies to functions
> written in *function* syntax, not to those in *method* syntax

with the accompanying example annotated "Ultimately an unsafe assignment, but not detected."
Underlying general rule, "Type Compatibility" → *Function Parameter Bivariance*: "assignment
succeeds if either the source parameter is assignable to the target parameter, or vice versa. This
is unsound…" VERIFIED.

Probe (`tsprobe3/variance2.js`), assigning `(x: string) => void` to each declaration style:

| declaration site | result |
|---|---|
| `interface MethodStyle { handle(x: string \| number): void }` | **no error** (bivariant) |
| `interface PropertyStyle { handle: (x: string \| number) => void }` | **TS2322** (contravariant) |

VERIFIED (probe).

**Consequence specific to JSDoc — and it cuts in the contract's favour.** A JSDoc `@property {(x:
string|number) => void} handle` is *property-with-function-type* syntax, so it gets the **strict**
contravariant check. Probe (`tsprobe3/jsdocvariance.js`) confirmed the JSDoc `@property` form errors
(TS2322) while an indexed-access extraction of a method-shorthand member (`{ handle(x): void
}['handle']`) does not. VERIFIED (probe).

So: **JSDoc typedefs cannot easily express the bivariant method-shorthand form, which means they are
accidentally stricter than a hand-written `.d.ts` interface using method syntax.** For an adapter
contract that is the behaviour you want — do not "fix" it by reaching for method shorthand. The
arity hole above remains regardless; variance and arity are independent.

---

## LANE 2 — runtime duck-type / structural validation at the load boundary

**Headline finding across five mature systems: not one validates a plugin object with a schema
validator, and almost none validates shape at *load* time. Every one hand-rolls `typeof x ===
'function'` or a single marker-property check, most of them lazily — at first use, not at
registration.**

### ESLint

- **Object format only in v9.** "ESLint v9.0.0 drops support for function-style rules. Function-style
  rules are rules created by exporting a function rather than an object with a `create()` method."
  (<https://eslint.org/docs/latest/use/migrate-to-9.0.0>) VERIFIED.
- **No load-time shape check; a generic duck-type at *lint* time.**
  `<https://raw.githubusercontent.com/eslint/eslint/v9.0.0/lib/linter/linter.js>` line 999, in
  `createRuleListeners`:
  ```js
  if (!rule || typeof rule !== "object" || typeof rule.create !== "function") {
      throw new TypeError(`Error while loading rule '${ruleContext.id}': Rule must be an object with a \`create\` method`);
  }
  ```
  VERIFIED. Its only call sites are inside the per-lint rule-execution loop, so a plugin exporting
  `{ meta }` with no `create` **imports fine and resolves config fine**, and throws only when a file
  is actually linted with that rule enabled. VERIFIED. A second runtime check follows: `The create()
  function for rule '${ruleId}' did not return an object.` (linter.js v9.0.0:1162) VERIFIED.
- **What *is* checked earlier is existence and options, not shape.** `RuleValidator.validate(config)`
  runs at config-resolution time from `lib/config/flat-config-array.js:211`, throwing `Could not find
  plugin "${pluginName}"` / `Could not find "${ruleName}" in plugin "${pluginName}"`. It never
  touches `create`. VERIFIED.
- **`meta.schema` validates rule OPTIONS, at config-resolution time, via ajv.** Docs: "Rules with
  options must specify a `meta.schema` property"; "For rules that don't specify a `meta.schema`
  property, ESLint throws errors when any options are passed"
  (<https://eslint.org/docs/latest/extend/custom-rules>) VERIFIED. Mechanism
  (`lib/config/flat-config-helpers.js`, `getRuleOptionsSchema`): a missing `meta.schema` returns
  `noOptionsSchema`, literally `Object.freeze({ type: "array", minItems: 0, maxItems: 0 })`, so any
  supplied option violates `maxItems: 0`. `schema: false` is the explicit opt-out. VERIFIED.

  *Path note:* `lib/config/rule-validator.js` no longer exists under `lib/config/` on `main` (ESLint
  10 moved it); the paths above are pinned to the **v9.0.0** tag.

### Rollup / Vite

- **Rollup does not validate plugin objects.** Docs: "A Rollup plugin is an object with one or more
  of the properties, build hooks, and output generation hooks described below"
  (<https://rollupjs.org/plugin-development/>) VERIFIED — no validation mentioned.
- Source (`src/utils/PluginDriver.ts`): hooks are collected guarded by `if (hook)`; an absent hook is
  skipped and unknown properties are never looked at. Only a *present* hook is type-checked, lazily
  and per-hook-name:
  ```ts
  function validateFunctionPluginHandler(handler, hookName, plugin) {
      if (typeof handler !== 'function') { error(logInvalidFunctionPluginHook(hookName, plugin.name)); }
  }
  ```
  VERIFIED.
- **Missing `name` is not an error** — `normalizePlugins` (`src/rollup/rollup.ts:186`) mutates the
  user's object, assigning `at position 3` from `ANONYMOUS_PLUGIN_PREFIX`. VERIFIED.
- **Unknown-property warnings exist but not for plugins.** `warnUnknownOptions` (code
  `UNKNOWN_OPTION`) is called only with `'input options'` and `'output options'`. VERIFIED.
- **Vite performs no shape validation either.** `packages/vite/src/node/config.ts`: `filterPlugin`
  drops falsy plugins, returns `true` if `!p.apply`, else calls/compares `p.apply`; `sortUserPlugins`
  reads `p.enforce`. No throw, no `name` check — the docs say `name` is "required" and nothing
  enforces it (<https://vite.dev/guide/api-plugin>). VERIFIED.

### PostCSS 8

**The only system in this survey with eager registration-time shape validation, keyed on one marker
property.** `lib/processor.js` `normalize()` runs in the `Processor` constructor and in `use()` — a
plain duck-type chain accepting `i.postcss === true`, `i.postcss`, `{plugins:[]}`, `{postcssPlugin}`,
or a bare `function`. Anything else falls to:

```js
} else { throw new Error(i + ' is not a PostCSS plugin') }
```

VERIFIED (<https://raw.githubusercontent.com/postcss/postcss/main/lib/processor.js>). Note the raw
interpolation: a plain object missing `postcssPlugin` surfaces as **`[object Object] is not a PostCSS
plugin`** — an attributability failure worth learning from.

PostCSS also does a genuine **unknown-property check**, the only one in the survey, in
`lib/lazy-result.js` `prepareVisitors()`: any capitalized key not in `PLUGIN_PROPS` throws ``Unknown
event ${event} in ${plugin.postcssPlugin}. Try to update PostCSS (${version} now).`` VERIFIED.

**REFUTED premise:** there is no "requires PostCSS 8" error in postcss core. Grep across
`processor.js`, `lazy-result.js`, `postcss.js`, `no-work-result.js` finds no such string. What exists
is a deprecation warning in `postcss.js:29` and a non-throwing `console.error` in `handleError`
("Unknown error from PostCSS plugin. Your current PostCSS version is X, but NAME uses Y…"). The
"requires PostCSS 8" phrasing lives in consumers/loaders, not postcss. REFUTED.

### Fastify

- At the literal moment `register()` is called, Fastify validates **only** that the plugin is a
  function or thenable. `register` is avvio's `use`; `Boot.prototype._addPlugin` calls
  `validatePlugin(pluginFn)`, throwing `AVV_ERR_PLUGIN_NOT_VALID` — `"Plugin must be a function or a
  promise. Received: '%s'"`. VERIFIED empirically (`f.register(42)` → `Received: 'number'`).
- **Everything else defers to boot and surfaces via `ready()`/`listen()`** — `lib/plugin-utils.js`
  runs `checkPluginHealthiness` → `checkVersion` → `checkDecorators` → `checkDependencies`. Version
  mismatch (`FST_ERR_PLUGIN_VERSION_MISMATCH`) fires from `ready()`, **not** `register()`. VERIFIED
  empirically.
- Encapsulation is a **symbol marker**: `shouldSkipOverride(fn)` = `!!fn[Symbol.for('skip-override')]`.
  `fastify-plugin` attaches exactly three symbols and validates three things, all sync `TypeError`s.
  VERIFIED.
- The one arity check anywhere in the survey: `fn.constructor.name === 'AsyncFunction' && fn.length
  === 3` → `FST_ERR_PLUGIN_INVALID_ASYNC_HANDLER`. Narrow, not general. VERIFIED.
- `name` is not required — fp defaults it to `getPluginName(fn) + '-auto-' + count++`. VERIFIED.
- Evidence spans fastify 5.12.0 / avvio 9.3.0 / fastify-plugin 5.1.0 (installed) vs `main` at
  6.0.0-alpha.1. fp has **no** semver check today (it moved into core); the exact version where it
  was removed is **UNVERIFIED**.

### Is a schema validator (zod/valibot) idiomatic for a function-bearing plugin object?

**No — overkill, unidiomatic, and with zod specifically, actively harmful.** Zero of the five mature
systems use one.

- **Current zod is 4.4.3.** VERIFIED (npm dist-tags).
- **Identity trap.** Zod's own migration guide still says "The result of `z.function()` is no longer
  a Zod schema. Instead, it acts as a standalone 'function factory'…"
  (<https://zod.dev/v4/changelog>) VERIFIED, but in 4.4.3 it *is* parseable again. The trap:
  `.parse()` does not return your function — it returns the `implement()` wrapper. `out === fn` is
  `false` and `out.length` is `0`, silently, **including inside `z.object()`**. VERIFIED empirically;
  undocumented. For a plugin contract this is disqualifying: you hand the host a different function
  than the author wrote, with its arity destroyed.
- **Arity** (`fn.length`) is statically checkable, but *not* by `z.function()` — a 3-param `input`
  schema parsed a 2-arg function with `success: true`. VERIFIED empirically. The working idiom is
  `z.custom(v => typeof v === 'function').check(z.property('length', z.literal(2)))`.
- **Parameter types and return type are invoke-only.** Docs: function schemas have an `.implement()`
  method "which accepts a function and returns a new function that automatically validates its
  inputs and outputs", throwing at *call* time (<https://zod.dev/api>). VERIFIED.
- **`z.custom()` gotcha, verbatim:** "If you don't provide a validation function, Zod will allow any
  value. This can be dangerous!" with `z.custom<{arg: string}>(); // performs no validation`
  (<https://zod.dev/api>) VERIFIED. `z.custom(v => typeof v === 'function')` and
  `z.instanceof(Function)` both reject non-functions **and preserve identity** — that identity
  preservation is the real reason to prefer them over `z.function()`. VERIFIED empirically.
- **Valibot** has `v.function()` but it is type-only: "With `function` you can validate the data type
  of the input" — no input/output params, so no arity or type validation at all
  (<https://valibot.dev/api/function/>). VERIFIED.

**Net:** a validator buys you `typeof === 'function'` plus `fn.length` over hand-rolled duck-typing —
a few lines — while `z.function()` makes it worse. The industry pattern is one marker property plus
`typeof` checks on handlers.

---

## LANE 3 — shared conformance test suite

### SQLAlchemy `sqlalchemy.testing.suite` — the primary exhibit

All source paths below are under
`https://raw.githubusercontent.com/sqlalchemy/sqlalchemy/main/`, fetched from `main`.

#### Consumption idiom

`README.dialects.rst` lines 165-171 (<https://raw.githubusercontent.com/sqlalchemy/sqlalchemy/main/README.dialects.rst>)
VERIFIED:

> `test_suite.py` - Finally, the ``test_suite.py`` module represents a stub test suite, which pulls
> in the actual SQLAlchemy test suite. To pull in the suite as a whole, it can be imported in one
> step::
>
> ```python
> # test/test_suite.py
>
> from sqlalchemy.testing.suite import *
> ```

**The import line is invariant; the path is not.** README shows `test/test_suite.py`, but neither
sampled real dialect uses it — the path is bound by pytest's `python_files` glob, not the framework.
VERIFIED:

- Snowflake — `tests/sqlalchemy_test_suite/test_suite.py:10`, `from sqlalchemy.testing.suite import *  # noqa`
  (<https://raw.githubusercontent.com/snowflakedb/snowflake-sqlalchemy/main/tests/sqlalchemy_test_suite/test_suite.py>)
- BigQuery — `tests/sqlalchemy_dialect_compliance/test_dialect_compliance.py:34`, same line
  (<https://raw.githubusercontent.com/googleapis/python-bigquery-sqlalchemy/main/tests/sqlalchemy_dialect_compliance/test_dialect_compliance.py>)

`lib/sqlalchemy/testing/suite/__init__.py` is 19 lines of pure re-export: `from .test_cte import *`,
then `test_ddl`, `test_dialect`, `test_insert`, `test_reflection`, `test_results`, `test_rowcount`,
`test_select`, `test_sequence`, `test_table_via_select`, `test_types`, `test_unicode_ddl`,
`test_update_delete`. VERIFIED.

Dialects then re-import individual classes under `_`-aliases to subclass and override (Snowflake
lines 11-22, e.g. `from sqlalchemy.testing.suite import FetchLimitOffsetTest as _FetchLimitOffsetTest`),
and may delete wholesale: `del ComponentReflectionTest  # require indexes not supported by snowflake`.
VERIFIED. **Note this escape hatch — deletion is available and used, and it is *invisible* compared
to the requirements mechanism below. It is the anti-pattern the requirements system exists to
replace.**

#### Wiring

`README.dialects.rst` lines 72-82 VERIFIED:

```ini
[tool:pytest]
addopts= --tb native -v -r fxX --maxfail=25 -p no:warnings
python_files=test/*test_*.py

[sqla_testing]
requirement_cls=sqlalchemy_access.requirements:Requirements
profile_file=test/profiles.txt

[db]
default=access+pyodbc://admin@access_test
sqlite=sqlite:///:memory:
```

Real files match exactly — BigQuery `requirement_cls=sqlalchemy_bigquery.requirements:Requirements`;
Snowflake `requirement_cls=snowflake.sqlalchemy.requirements:Requirements`. VERIFIED. Whether a
`pyproject.toml` path exists is **UNVERIFIED** — the read is
`file_config.get("sqla_testing", "requirement_cls")` (`plugin_base.py:475`), a configparser/INI call,
and both sampled dialects use `setup.cfg`.

`conftest.py` (README lines 96-103) VERIFIED:

```python
from sqlalchemy.dialects import registry
import pytest

registry.register("access.pyodbc", "sqlalchemy_access.pyodbc", "AccessDialect_pyodbc")
pytest.register_assert_rewrite("sqlalchemy.testing.assertions")

from sqlalchemy.testing.plugin.pytestplugin import *
```

`--dburi`: `plugin_base.py:88-93`, `help="Database uri.  Multiple OK, first one is run by default."`
Consumed at line 430 and fed to `provision.setup_config(...)` at 466 — so it is simultaneously the
live-DB switch **and** the provisioning trigger. VERIFIED.

The `sqlalchemy.dialects` entry-point group makes the dialect addressable from `create_engine()`:
`"access.pyodbc = sqlalchemy_access.pyodbc:AccessDialect_pyodbc"` enables
`create_engine("access+pyodbc://user:pw@dsn")`. VERIFIED (README lines 56-64).

#### `provision.py`

Base hooks in `lib/sqlalchemy/testing/provision.py` all `raise NotImplementedError` until a dialect
registers one: `create_db` ("Dynamically create a database for testing. Used when a test run will
employ multiple processes, e.g., when run via `tox` or `pytest -n4`.", lines 363-372), `drop_db`,
`temp_table_keyword_args` ("return the kwargs that are passed to the Table method when creating a
temporary table", 470-480), plus `get_temp_table_name`, `set_default_schema_on_connection`, `upsert`,
`drop_all_schema_objects`, `run_reap_dbs`, `configure_follower`. VERIFIED.

**Location and discovery — README is silent here, and the natural guess is wrong.** It lives in the
**dialect package**, not `test/` — e.g. `src/snowflake/sqlalchemy/provision.py`. Discovery is
`provision.setup_config` → `dialect.load_provisioning()` (provision.py:85) →
`engine/default.py:737-743` VERIFIED:

```python
@classmethod
def load_provisioning(cls):
    package = ".".join(cls.__module__.split(".")[0:-1])
    try:
        __import__(package + ".provision")
    except ImportError:
        pass
```

Registration is by decorator, dispatched on URL backend name (provision.py:44-71). Snowflake's real
file VERIFIED:

```python
@create_db.for_db("snowflake")
def _snowflake_create_db(cfg, eng, ident):
    with eng.begin() as conn:
        conn.exec_driver_sql(f"CREATE SCHEMA IF NOT EXISTS {ident}")
```

#### THE KEY MECHANISM — declaring a capability is NOT supported

**Exact names.** Config key `requirement_cls` under `[sqla_testing]`; CLI override `--requirements`
(`plugin_base.py:175-179`, `help="requirements class for testing, overrides setup.cfg"`). Both
resolve through `_setup_requirements(argument)` (479-492), which splits on `:`, imports, and does
`config.requirements = testing.requires = req_cls()`. VERIFIED. README lines 160-163 shows the
combined invocation:

```
pytest -v --requirements sqlalchemy_access.requirements:Requirements \
          --dburi access+pyodbc://admin@access_test
```

**Verbatim from `lib/sqlalchemy/testing/requirements.py`**, class `SuiteRequirements(Requirements)`
(line 36) VERIFIED:

```python
@property
def create_table(self):
    """target platform can emit basic CreateTable DDL."""
    return exclusions.open()

@property
def create_table_as(self):
    """target platform supports CREATE TABLE AS SELECT."""
    return exclusions.closed()

@property
def json_type(self):
    """target platform implements a native JSON type."""
    return exclusions.closed()

@property
def duplicate_key_raises_integrity_error(self):
    """target dialect raises IntegrityError when reporting an INSERT
    with a primary key violation.  (hint: it should)
    """
    return exclusions.open()

@property
def sane_rowcount(self):
    return exclusions.skip_if(
        lambda config: not config.db.dialect.supports_sane_rowcount,
        "driver doesn't support 'sane' rowcount",
    )
```

**Default posture: there is no global default — and this is the design lesson.** Scripted counts over
the file give 79 `exclusions.open()` against 112 `exclusions.closed()` occurrences (VERIFIED by
`grep -c`). `SuiteRequirements` is a *concrete* class; every requirement carries its own explicit,
individually-argued default, and a dialect that declares nothing inherits that per-property mix. A
third posture exists: `sane_rowcount` is *computed* from a dialect attribute rather than hardcoded.
So the contract author decides, capability by capability, whether silence means yes or no.

**Real gating use** — `lib/sqlalchemy/testing/suite/test_types.py:1252`, gating `BooleanTest.test_null`:

```python
@testing.requires.nullable_booleans
def test_null(self, connection):
    ...
    eq_(row, (None, None))
```

Class-level form — `test_types.py:687-691`:

```python
class DateTimeMicrosecondsTest(_DateFixture, fixtures.TablesTest):
    __requires__ = ("datetime_microseconds",)
```

Resolved in `plugin_base.py:659-671` by `getattr(requirements, requirement)` then
`check.matching_config_reasons(config_obj)`. VERIFIED.

**`open()` vs `closed()` semantics** — `exclusions.py:457-462`, entire bodies VERIFIED:

```python
def open():  # noqa
    return skip_if(BooleanPredicate(False, "mark as execute"))

def closed(reason="marked as skip"):
    return skip_if(BooleanPredicate(True, reason))
```

Both are `skip_if` over a constant predicate: `open()` never skips, `closed()` always skips.

**Skip vs xfail are distinct categories — and this is what makes it a conformance suite rather than a
mute button.** `skip_if(predicate)` adds to `rule.skips`; `fails_if(predicate)` adds to `rule.fails`
(`exclusions.py:20-31`); `compound.__init__` keeps `self.fails`/`self.skips` as separate sets, and
`as_skips()` (50-54) exists precisely to fold fails into skips. So:

- `only_on(dbs)` = `only_if(OrPredicate(...))` = `skip_if(NotPredicate(...))` — run *only* on the
  listed backends.
- `skip_if` — don't run.
- `fails_if` / `fails_on(db)` (`fails_on` is literally `return fails_if(db, reason)`, line 473) —
  **run it and expect failure**, so an *unexpected pass* is itself a failure.

VERIFIED. That last one is the mechanism a naive "just skip what you don't support" design lacks: a
declared non-capability that quietly starts working is a contract drift, and `fails_if` catches it.

#### What the suite asserts that a type checker never could

Every example below is a **wrong VALUE** or **wrong BEHAVIOUR** defect wearing a correct type.

**(a) Wrong VALUE — silent precision truncation.** `test_types.py:687-691` + `_DateFixture.test_round_trip`
(591-601) VERIFIED:

```python
class DateTimeMicrosecondsTest(_DateFixture, fixtures.TablesTest):
    __requires__ = ("datetime_microseconds",)
    datatype = DateTime
    data = datetime.datetime(2012, 10, 15, 12, 57, 18, 39642)
```
```python
row = connection.execute(select(date_table.c.date_data)).first()
compare = self.compare or self.data
eq_(row, (compare,))
assert isinstance(row[0], type(compare))
```

A driver that drops microseconds still returns a `datetime` — perfectly typed, wrong value.

**(b) Wrong VALUE — matched-vs-changed rowcount semantics.** `suite/test_rowcount.py:129-139` VERIFIED:

```python
def test_update_rowcount2(self, connection):
    # WHERE matches 3, 0 rows changed
    r = connection.execute(
        employees_table.update().where(department == "C"),
        {"department": "C"},
    )
    eq_(r.rowcount, 3)
```

`int` either way; only execution catches a driver returning 0.

**(c) Wrong VALUE — boolean marshalling.** `test_types.py:1245-1250`: `eq_(row, (True, False))` then
`assert isinstance(row[0], bool)` — catches a driver handing back `1`/`0`. VERIFIED.

**(d) Wrong BEHAVIOUR — exception translation.** `suite/test_dialect.py:117-130` VERIFIED:

```python
@requirements.duplicate_key_raises_integrity_error
def test_integrity_error(self):
    ...
        assert_raises(
            exc.IntegrityError,
            conn.execute,
            self.tables.manual_pk.insert(),
            {"id": 1, "data": "d1"},
        )
```

A dialect that lets the raw DBAPI error through, or maps it to `OperationalError`, is statically
indistinguishable from a correct one. **This is the exact analogue of the JS adapter's
error-signalling-convention defect** — the contract says "signal failure *this* way", and only
running the code proves it.

**(e) Wrong VALUE — Decimal fidelity.** `test_types.py:1148-1156`, `test_precision_decimal`
round-trips `Decimal("54.234246451650")`, `Decimal("0.004354")`, `Decimal("900.0")` through
`Numeric(precision=18, scale=12)`; float-coercing drivers return a `Decimal` of the wrong magnitude.
VERIFIED.

#### What to carry into a JS adapter contract

1. The suite is **imported wholesale**, not copied — `from sqlalchemy.testing.suite import *`.
2. Capability declaration is a **separate, named, pointed-at artifact** (`requirement_cls`), not
   inline skips scattered through tests.
3. The base class states an **explicit per-capability default**, so silence has a defined meaning.
4. **Skip and expected-failure are different things**; the latter catches drift in a declared
   non-capability.
5. Deleting a test class is possible and invisible — the requirements mechanism exists precisely to
   make non-conformance *declared* rather than *hidden*.

### ESLint `RuleTester` — the behavioural-contract exhibit

**Rule shape is enforced up front.** v9.0.0 `lib/rule-tester/rule-tester.js:551-553`
(<https://raw.githubusercontent.com/eslint/eslint/v9.0.0/lib/rule-tester/rule-tester.js>) VERIFIED:

```js
if (!rule || typeof rule !== "object" || typeof rule.create !== "function") {
    throw new TypeError("Rule must be an object with a `create` method");
}
```

**Test-case surface** (<https://eslint.org/docs/latest/integrate/nodejs-api>): `code` required;
`errors` "(number or array, **required**)"; `output` "(string, **required if the rule fixes code**)
… If this is `null` or omitted, asserts that none of the reported problems suggest autofixes."
VERIFIED.

**ESLint v9 made RuleTester stricter — eleven documented items**, all from the official migration
guide § "Stricter `RuleTester` checks"
(<https://eslint.org/docs/latest/use/migrate-to-9.0.0#stricter-rule-tester>). The guide's preamble:
"In order to aid in the development of high-quality custom rules that are free from common bugs,
ESLint v9.0.0 implements several changes to `RuleTester`". ALL VERIFIED:

1. Test case `output` must be different from `code`.
2. Test error objects must specify `message` or `messageId`.
3. Test error object must specify `suggestions` if the actual error provides suggestions — "omitting
   the `suggestions` property asserts that the actual error does not provide suggestions".
4. Test suggestion objects must specify `output`.
5. Test suggestion objects must specify `desc` or `messageId` — "It's also not allowed to specify
   both."
6. Suggestion messages must be unique.
7. Suggestions must change the code.
8. Suggestions must generate valid syntax — "`RuleTester` now **parses the output of suggestions**
   using the same language options as the `code` value and throws an error if parsing fails."
9. Test cases must be unique.
10. `filename` and `only` must be of the expected type.
11. Messages cannot have unsubstituted placeholders.

**Answers to the specific sub-questions:**

- **Missing `output` on a fixable result — hard failure.** v9.0.0 rt.js:1234-1239:
  `assert.strictEqual(result.output, item.code, "The rule fixed the code. Please add 'output'
  property.")`. VERIFIED.
- **Unknown properties — a three-way split, and a correction to the premise.** *Error* objects:
  rejected (rt.js:1029, allowed set `message, messageId, data, line, column, endLine, endColumn,
  suggestions`). *Suggestion* objects: rejected (rt.js:1126). ***Test-case top level: NOT
  rejected.*** Known `RuleTesterParameters` are deleted and everything else becomes flat config —
  docs: "Any additional properties of a test case will be passed directly to the linter as config
  options." An unknown key fails only if flat-config validation rejects it. VERIFIED — **partial
  REFUTATION** of "rejects unknown properties" as a blanket claim.
- **`messageId` must exist in `meta.messages`** — yes. rt.js:1038-1044: "Error can not use
  'messageId' if rule under test doesn't define 'meta.messages'." plus ``Invalid messageId
  '${error.messageId}'. Expected one of ${friendlyIDList}.`` VERIFIED.
- **Freezing.** RuleTester deep-freezes three `context` properties (v9.0.0 rt.js:602-606):
  `freezeDeeply(context.options)`, `.settings`, `.parserOptions` — with the `languageOptions` line
  **commented out in shipped source**. Test-case objects themselves are **not** `Object.freeze`d
  (grep negative). The `context` object itself is frozen by the **Linter**, not RuleTester
  (linter.js v9.0.0:1040,1082). VERIFIED.
- **Bonus enforcement not in the eleven:** RuleTester snapshots the AST before and after and fails on
  mutation — rt.js:852-856, `assert.fail("Rule should not modify AST.")`. VERIFIED.

**Why a type checker cannot substitute — the class of defect.** Every assertion above is a
*value-level fact about a computation over a specific input*, not a shape:

- "For source `foo()`, one pass of the fixer emits exactly `foo();`" — a `fix()` returning
  `{range, text}` is perfectly well-typed while producing a syntactically broken splice. Item 8
  exists *because* well-typed fixers emit invalid syntax.
- "The error lands at line 3, column 7." Off-by-one range arithmetic type-checks flawlessly.
- "The rendered message has no `{{ name }}` left in it" — `messageId: "x"` with a message needing
  `data.name` is fully typed and fully broken (item 11).
- "The rule did not mutate the AST" — absence of a side effect on a shared mutable structure. No
  mainstream type system tracks this, yet a mutating rule silently corrupts every *later* rule.

### Other exhibits (shared idea)

- **Jakarta EE / Java TCK.** The normative obligation is in the Eclipse Foundation Specification
  Process (<https://www.eclipse.org/projects/efsp/>): "A Compatible Implementation must fulfil all
  requirements of a Final Specification including all requirements of the corresponding TCK and be in
  compliance with the Eclipse Foundation TCK License." A spec cannot reach Final without at least one
  Compatible Implementation passing it. Enforcement is legal/trademark, not tooling. VERIFIED —
  *correction:* the obligation is **not** on the `tckprocess/` page, which is filing procedure.
- **Kubernetes conformance.** <https://raw.githubusercontent.com/cncf/k8s-conformance/master/instructions.md>:
  "The standard set of conformance tests is currently those defined by the `[Conformance]` tag in the
  kubernetes e2e suite"; "The standard tools for running these tests are Sonobuoy and Hydrophone"; "A
  valid certification run may not skip any conformance tests." VERIFIED — *correction:* Sonobuoy is
  one of **two** sanctioned runners, not the only one.
- **web-platform-tests.** "a cross-browser test suite for the Web-platform stack. Writing tests in a
  way that allows them to be run in all browsers gives browser projects confidence that they are
  shipping software that is compatible with other implementations."
  (<https://raw.githubusercontent.com/web-platform-tests/wpt/master/README.md>) One shared suite, a
  public scoreboard at wpt.fyi, no gate. VERIFIED.
- **`php-http/psr7-integration-tests` — the closest structural analogue.** Install `composer require
  --dev php-http/psr7-integration-tests`. The suite ships abstract PHPUnit cases; the consumption
  idiom is **extend + implement one factory method**
  (<https://raw.githubusercontent.com/php-http/psr7-integration-tests/master/README.md>):
  ```php
  class RequestTest extends RequestIntegrationTest {
      public function createSubject(): RequestInterface { return new Request('GET', '/'); }
  }
  ```
  Factory methods are `createSubject()`, `createStream($data)`, `createUri($uri)`. Non-conformance is
  declared declaratively via `protected $skippedTests = ['testMethodIsCaseSensitive' => '…']`.
  VERIFIED.
- **`abstract-level` — the best JS exhibit.**
  <https://raw.githubusercontent.com/Level/abstract-level/main/README.md> § *Test Suite*: "To prove
  that your implementation is `abstract-level` compliant, include the abstract test suite in your
  `test.js`". The idiom is **import a suite function and hand it a factory**, not subclassing:
  ```js
  const suite = require('abstract-level/test')
  suite({ test, factory (options) { return new ExampleLevel(options) } })
  ```
  "The `factory` option must be a function that returns a unique and isolated instance of your
  implementation. The factory will be called many times by the test suite." Optional capabilities are
  declared through `db.supports`, and the README frames the skip as a feature: "This also serves as a
  signal to users of your implementation." VERIFIED.

  **This is the shape to copy.** It is `describeAdapterContract(makeAdapter, caps)` in all but name,
  already proven in the JS ecosystem.

- **Verified negatives — do not cite these as conformance suites.** `aria-query` is a data library
  ("Programmatic access to the WAI-ARIA 1.2 Roles Model", org is `A11yance`).
  `@es-joy/jsdoccomment` is a parsing utility. `readable-stream` publishes only `["lib", "LICENSE",
  "README.md"]` — no consumable test export. All VERIFIED negative.

### VITEST specifically

**Vitest has NO built-in RSpec-style `shared_examples`.** VERIFIED — checked as an explicit absence
against the official API reference (<https://vitest.dev/api/>), which enumerates `test`,
`test.extend`, `test.skip/skipIf/runIf/only/concurrent/todo/fails`, `test.each`, `test.for`,
`describe` and its modifiers, the hooks, and `bench`. No `shared_examples`, `sharedExamples`, or
`behaves like` construct exists.

**The idiomatic shape is exactly the one proposed: an exported function from a non-`.test.js` module
that each adapter's own test file imports and calls.** VERIFIED empirically (vitest 4.1.10).

Probe (`vitestprobe/`), three files — `contract-suite.js` (no `.test.` in the name, so not collected
as a test file) exporting `describeAdapterContract(label, makeAdapter, caps)` which calls
`describe`/`it` internally, plus `good.test.js` and `bad.test.js` that import and invoke it:

```
 ✓ good.test.js > Adapter contract: good > exposes a string name
 ✓ good.test.js > Adapter contract: good > fetchOne resolves to a {ok, body} shape, not a rejected promise
 ✓ good.test.js > Adapter contract: good > signals failure as a Result, never a rejection
 ✓ good.test.js > Adapter contract: good > fetchMany returns one entry per id
 ✓ bad.test.js  > Adapter contract: bad > exposes a string name
 ✓ bad.test.js  > Adapter contract: bad > fetchOne resolves to a {ok, body} shape, not a rejected promise
 × bad.test.js  > Adapter contract: bad > signals failure as a Result, never a rejection
   → promise rejected "Error: boom" instead of resolving
 ↓ bad.test.js  > Adapter contract: bad > fetchMany returns one entry per id

 Test Files  1 failed | 1 passed (2)
      Tests  1 failed | 6 passed | 1 skipped (8)
```

Confirmed by this run, all VERIFIED:

- **`describe`/`it` may legally be called from an imported helper inside a test file.** Vitest
  collects by *executing* the test file; a helper invoked at module scope registers its suites
  normally.
- **Attribution is per-file and correct** — `good.test.js > Adapter contract: good > …`. Each adapter
  owns its own file, its own failures, and its own fixtures.
- **Optional capabilities work via `it.skipIf(!caps.supportsMany)`**, and the skip is *visible*
  (`↓`), matching the `abstract-level`/`psr7` posture that a declared non-capability is a signal, not
  a silent hole.
- **The decisive result:** `bad.test.js`'s adapter is **structurally perfect** — every required
  member, correct arity, correct declared types. It would satisfy `@type {Adapter}` and
  `@satisfies {Adapter}` without a single diagnostic. It fails the suite because it **rejects instead
  of returning a failure `Result`**. That is the wrong-error-signalling-convention defect named in
  the cross-cutting question, caught by Lane 3 and invisible to Lanes 1 and 2.

**`describe.each` / `test.each` as the table-driven alternative, and its limits.** `each` supports
arrays-of-arrays and template-literal tables with printf-style placeholders (`%s`, `%d`, `%o`, `%#`,
`%$`) (<https://vitest.dev/api/>) VERIFIED. **Limit:** `each` parameterises cases *within one file*.
It is the right tool when one owner enumerates all adapters centrally, and the wrong tool for an
adapter contract, because it cannot give each adapter its own test file, its own setup/teardown, its
own capability declaration, or its own independently-runnable failure. `describeAdapterContract` and
`describe.each` compose — the suite can use `each` internally for its own table-driven cases.

**`test.extend`, `expect.extend`, workspace/projects — checked, largely orthogonal.**
- `test.extend` "extend[s] the test context with custom fixtures. This will return a new `test` and
  it's also extendable" (<https://vitest.dev/api/>) VERIFIED. It is a *fixture-injection* mechanism,
  not a shared-suite mechanism; it is useful *inside* a contract suite (to supply a fresh adapter per
  test with automatic teardown) but does not replace the exported-function idiom. Note the extended
  `test` must be threaded into the suite function if you want adapters to supply fixtures.
- `expect.extend` adds custom matchers — genuinely useful for a contract suite (e.g. a
  `toBeFailureResult()` matcher shared across adapters) but again orthogonal to suite sharing.
- Workspace/projects config bears on this only if each adapter is a separate package needing its own
  environment or config; it is a *packaging* decision, not a contract-enforcement one. **UNVERIFIED
  in detail** — not probed, and not load-bearing for the idiom choice.

---

## CROSS-CUTTING ANSWERS

### Which lane is the ONLY one that catches "the adapter produced the wrong thing"?

**Lane 3, the shared conformance suite. Unambiguously, and by construction.**

Framed by *when and to whom*:

- **Wrong return shape.** Lane 1 checks the *declared* return type; it cannot check the value. An
  adapter annotated `Promise<{ok, body}>` that resolves `{ok: true}` with `body` undefined
  type-checks (and if the object is built indirectly, even excess/missing members escape — §3(i)).
  Lane 2 sees only that `fetchOne` is a function; it does not call it. Lane 3 asserts on the actual
  resolved value.
- **Wrong error-signalling convention.** *Demonstrated, not argued*: the vitest probe's `bad` adapter
  rejects where the contract says return a failure `Result`, is structurally flawless, passes Lane 1
  silently, passes any Lane 2 presence check, and fails Lane 3. The rejection path is simply not in
  the type — `Promise<T>` says nothing about whether it rejects.
- **Wrong fallback when an optional method is absent.** This is a property of the *host's* behaviour
  in combination with the adapter, so no per-adapter shape check can reach it. It needs the suite to
  run the host path against an adapter that genuinely lacks the method — which is precisely what a
  capability-parameterised suite (`caps.supportsMany` → `it.skipIf`, SQLAlchemy's
  `@testing.requires.*`, `abstract-level`'s `db.supports`) is for.

The general rule: **Lanes 1 and 2 both check shape and differ only in timing and visibility; Lane 3
is the only lane that executes the adapter.** Any defect that requires running code to observe is
Lane 3's alone. The arity hole (§6) is the sharpest illustration — an adapter that silently ignores
its `opts`/`timeout` parameter is a *type-correct* wrong-behaviour defect that only execution reveals.

### Is runtime method-presence checking worth its weight when a type checker genuinely runs in CI?

**For it:** it converts a defect from "`TypeError: a.fetchMany is not a function` in a stack trace
three layers deep, at 3am, blamed on the host" into "adapter `foo` is missing `fetchMany`, at
registration, blamed on `foo`". That is **attributability**, and it is a different product from
correctness. It is also the *only* lane that sees a module the type checker never compiled — a
third-party adapter shipped as a package, a runtime-interpolated path (§3(iii)), a JS file behind
`allowJs:false`, or a file carrying `// @ts-nocheck`. And it costs ~10 lines. PostCSS's eager
`normalize()` is the whole pattern; note also that PostCSS's raw interpolation produces `[object
Object] is not a PostCSS plugin`, which is the attributability lesson in the negative — if you build
this, name the adapter.

**Against it:** it is strictly redundant for any adapter the type checker actually compiled, since
Lane 1 already catches missing and wrong-typed members (§3(i)) at a strictly earlier moment and with
a better error. It duplicates the contract in a second place that can drift from the typedef. And —
the evidence from Lane 2 — it buys much less than it appears to: it can check presence and `typeof`,
and essentially nothing else. It cannot check arity meaningfully (only Fastify does an arity check
anywhere in the survey, and only for one narrow async-handler case), cannot check parameter or return
types without invoking, and a schema validator does not rescue it (zod's `z.function()` actively
destroys arity and identity). A presence check that passes tells you almost nothing.

**The condition that decides it: is the adapter set closed and type-checked in the same CI run, or is
it open?**

- **Closed** — every adapter lives in this repo, is enumerated in a registry, and is compiled by the
  same `tsc` invocation that gates the merge. Lane 1 already gives load-time-equivalent coverage;
  runtime presence checking is near-redundant ceremony. Spend the effort on Lane 3 instead.
- **Open** — adapters arrive as third-party packages, are discovered at runtime, or are otherwise
  loaded by a path no compiler saw. Lane 1 provides *zero* guarantee about the loaded module
  (§3(iii)), and the load-boundary check is the only thing standing between a malformed adapter and a
  confusing crash in unrelated code. Do it, keep it minimal, and make the message name the adapter.

Every mature system surveyed in Lane 2 is in the *open* category, and every one of them does the
minimal version of exactly this — which is the strongest available evidence for the condition.

### Verify or refute: "a type checker cannot see an adapter module resolved by a runtime-interpolated dynamic import path, so for dynamically-loaded plugins the type lane provides zero load-time guarantee."

**The first clause is VERIFIED. The second is VERIFIED as stated but is a conditional that the
counter-proposal defuses — so the sentence is true only for a genuinely open adapter set.**

*First clause, VERIFIED (probe, §3(iii)):* `await import(\`./adapters/${name}.js\`)` resolves to
`any`, versus a real module type for a static specifier. Worse than "cannot see it": the `any`
propagates, so `mod.thisMethodDoesNotExist(1,2,3).andNeitherDoesThis` compiles clean. The type lane
does not merely abstain — it stops checking the host's consumption of the adapter too.

*The counter-proposal — a static registry of static imports — does restore type visibility.*
**VERIFIED (probe, `tsprobe5/registry.js`).** An annotated registry catches a non-conforming adapter
at the registry site, even though that adapter's own file carries no annotation at all:

```
registry.js(10,3): error TS2741: Property 'fetchOne' is missing in type '{ name: string; }'
                   but required in type 'Adapter'.
```

**And — the important result — it works lazily too.** The standard objection is that a registry of
static imports forces eager loading of every adapter. It does not. Static specifiers inside thunks
are fully checked:

```js
/** @type {Record<string, () => Promise<{ adapter: import('./contract.js').Adapter }>>} */
export const lazyRegistry = {
  good: () => import('./adapters/good.js'),
  broken: () => import('./adapters/broken.js'),
};
```
```
registry.js(17,17): error TS2322: Type 'Promise<{ adapter: { name: string; }; … }>' is not
  assignable to type 'Promise<{ adapter: Adapter; }>'. … Property 'fetchOne' is missing …
```

VERIFIED (probe). Consumers also get a real type rather than `any` — `registry[key].noSuchMethod()`
produced `TS2339: Property 'noSuchMethod' does not exist on type 'Adapter'`. VERIFIED.

**So the precise, non-hand-wavy answer:** the constraint that costs you the type lane is
**enumeration, not laziness, and not dynamism per se**. A project that can list its adapters in one
annotated registry keeps full static conformance checking *and* lazy loading, and has no reason to
accept `any`. A project whose adapter set is genuinely open — third-party packages resolved from
config at runtime — cannot enumerate, genuinely gets `any`, and for it the original claim holds
exactly as stated. That is the same closed-vs-open condition that decides the runtime-check question
above; it is one condition, not two.

**Caveat on the registry, so it is not oversold:** the registry restores *shape* checking only. It
does not close the arity hole (§6), does not survive `// @ts-nocheck` in an adapter file without the
`ban-ts-comment` lint rule, and catches nothing behavioural. It moves the type lane from *zero* to
*shape*, which is real but bounded. Lane 3 remains the only lane that runs the adapter.
