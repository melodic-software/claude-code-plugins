---
topic: js-adapter-contract-design
section: evolution
abstract: "No surveyed system versions its plugin contract — the contract version IS the host's major version; object-vs-positional is the wrong axis (requiredness is the variable), and having no external adapter authors removes the need for compatibility machinery but none of the need for clarity machinery."
claims:
  - claim: "Zero of ~15 surveyed systems (PostCSS, ESLint, Rollup, Vite, Prettier, webpack) have a plugin-declared contract-version field; the universal mechanism is host-package semver via peerDependencies plus a migration guide."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://docs.npmjs.com/cli/v10/configuring-npm/package-json#peerdependencies"
        tier: 1
        pool: "npm"
      - url: "https://eslint.org/version-support/"
        tier: 1
        pool: "ESLint"
  - claim: "Behaviour-branching on a declared version has zero observed instances; webpack's this.version = 2 is documented for backward-compat branching yet is a frozen literal identical at v2.7.0, webpack-4 and main, carrying no information through the 4->5 break."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://webpack.js.org/api/loaders/"
        tier: 1
        pool: "webpack"
  - claim: "REFUTED premise: PostCSS 8 did not break old plugins — the 'requires PostCSS 8' error is thrown by PostCSS 7 (shipped in 7.0.33 one day after 8.0.0); PostCSS 8 still runs v7 function plugins, so the break is forward-only."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://raw.githubusercontent.com/postcss/postcss/main/lib/lazy-result.js"
        tier: 1
        pool: "PostCSS"
      - url: "https://evilmartians.com/chronicles/postcss-8-plugin-migration"
        tier: 2
        pool: "Evil Martians (PostCSS maintainer-adjacent)"
  - claim: "Object-vs-positional is the wrong axis — REQUIREDNESS is the variable. A missing REQUIRED property is an assignability failure (TS2741) that fires regardless of literal freshness; the real hole is partial overlap, and @satisfies on a named const recovers excess-property checking."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://www.typescriptlang.org/docs/handbook/2/objects.html"
        tier: 1
        pool: "Microsoft/TypeScript"
      - url: "local probe: tsc 7.0.2, weak-type detection (TS2559) and partial-overlap hole reproduced"
        tier: 0
        pool: "first-party empirical (this machine)"
  - claim: "Extensible argument objects are safe HOST->PLUGIN (unknown fields ignored) but hazardous PLUGIN->HOST (a typo is a silent behaviour change); Node's one added plugin->host obligation, shortCircuit, was made a throwing requirement rather than an optional field."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://nodejs.org/api/module.html"
        tier: 1
        pool: "Node.js"
      - url: "https://github.com/nodejs/node/pull/37468"
        tier: 1
        pool: "Node.js"
  - claim: "The dominant strategy for a new required capability is optional-plus-HOST-SIDE-default; a spread-in base object couples every plugin to a snapshot of the defaults, reintroducing the problem it claims to solve."
    confidence: MEDIUM
    tiers: [1]
    sources:
      - url: "https://nodejs.org/api/module.html"
        tier: 1
        pool: "Node.js"
      - url: "https://github.com/eslint/rfcs/blob/main/designs/2021-schema-object-rules/README.md"
        tier: 1
        pool: "ESLint"
produced_by: lane-d
---

# (d) Contract EVOLUTION: widening a required method's signature, and adding a required method, without breaking existing adapters

Research pass for the source-adapter contract design. Every claim carries an inline URL and a
confidence marker.

## Confidence markers used

Matching the convention established by the sibling `e-design-rule.md` and `b-optional-and-capabilities.md`
in this directory — two orthogonal axes:

- **VERIFIED / UNVERIFIED / REFUTED** — whether the claim is supported by a source I reached. A
  fourth marker, **INFERENCE**, tags conclusions I drew *across* verified facts rather than read in
  any source; those are my reasoning and carry my fallibility, not a citation's authority.
- **`[EXACT]` / `[SUBSTANCE]`** — quote fidelity. `[EXACT]` = extracted byte-for-byte from primary
  text (raw source fetched with `curl` and read locally, or executed locally). `[SUBSTANCE]` = the
  substance is verified but wording is not guaranteed verbatim.

All primary text in this document was fetched raw on 2026-08-14 from `raw.githubusercontent.com`,
the npm registry, or official docs sites, and read locally. Question A was settled by **running
TypeScript 7.0.2 locally against JSDoc-annotated ESM `.js` fixtures on Node 24.18.0**, not by
citation — the transcript is in §7.1.

---

## 0. Premises in the brief that are WRONG — refuted up front

Five corrections. Each matters to the design conclusion, not just to accuracy.

### 0.1 REFUTED — Rollup's object hook form does NOT widen a hook's *signature*

The brief describes the `{ order, handler, sequential }` form as "widening a hook's contract without
breaking existing plugins." That is **half right and the wrong half is load-bearing.**

What was widened is the **hook value's shape** — the slot `plugin.transform` may now hold either a
function or an object carrying the function plus *dispatch metadata*. The **handler's own signature
is untouched**: `transform(code, id)` before, `transform(code, id)` after. Nothing was added to the
argument list, and no existing handler had to change.

This distinction is the whole point for our purposes. Rollup did not solve "I need to pass a new
argument to an existing hook." It solved a *different* problem — "I need the plugin to tell the host
something about **how to call** the hook" — and the technique it used (union of old shape and richer
new shape) is genuinely the technique the brief is after. Calling it signature-widening would lead
us to copy it for a problem it does not address. See §1.5 for what Rollup actually did when it
needed to widen a hook's *arguments*: it widened the trailing options **object**, positionally.

VERIFIED against the type definition and the docs (§1.2, §1.3).

### 0.2 REFUTED — Node's module customization hooks are not, and never were, REQUIRED

The brief calls Node "the strongest 'we consolidated several required hooks into one' precedent."
The hooks are **all optional**. `module.registerHooks(options)`'s own parameter documentation says
so explicitly — VERIFIED `[EXACT]`,
<https://raw.githubusercontent.com/nodejs/node/main/doc/api/module.md>:

> * `options` {Object}
>   * `load` {Function|undefined} See [load hook][]. **Default:** `undefined`.
>   * `resolve` {Function|undefined} See [resolve hook][]. **Default:** `undefined`.

Both hooks default to `undefined`. A hooks module supplying neither is legal and inert. The
consolidation was of *optional* hooks into *fewer optional* hooks. This matters because "Node
consolidated required hooks" would be a precedent for breaking required surface; what Node actually
demonstrates is narrower and more useful (§2).

### 0.3 REFUTED — `dynamicInstantiate` was not part of the `load`/`resolve` consolidation

The brief groups `dynamicInstantiate` with `getFormat`/`getSource`/`transformSource` as
consolidated into `load`. It was not. It was removed **separately and earlier**, in the Node 14
line — VERIFIED `[EXACT]`,
<https://raw.githubusercontent.com/nodejs/node/main/doc/changelogs/CHANGELOG_V14.md>:

> `**module**: remove dynamicInstantiate loader hook (Jan Krems) [#33501](https://github.com/nodejs/node/pull/33501)`

It has no successor hook. It was deleted, not folded in. (It does reappear in v16.12.0's
*obsolete-hook detector* — see §2.4, which is a separate and interesting fact.)

### 0.4 REFUTED — PostCSS 8 did not break old plugins. The break ran the OTHER direction

This is the largest correction in the document and it inverts the exhibit's lesson.

The famous error string `PostCSS plugin X requires PostCSS 8` is **thrown by PostCSS 7, not by
PostCSS 8.** PostCSS 8 accepts and executes PostCSS 7 plugins unchanged, and still does today.
VERIFIED `[EXACT]`, current `main` (8.5.26),
<https://raw.githubusercontent.com/postcss/postcss/main/lib/lazy-result.js> — the v7 calling
convention is live in the dispatcher:

```js
      } else if (typeof plugin === 'function') {
        return plugin(this.result.root, this.result)
      }
```

And stated outright by the project — VERIFIED `[EXACT]`,
<https://github.com/postcss/postcss/wiki/PostCSS-8-for-end-users>:

> "PostCSS 8 supports plugins from PostCSS 7. You just need to update `postcss` dependency and tool,
> which run `postcss` (like `postcss-loader` or `postcss-cli`). But some PostCSS runners didn't
> publish a new version with PostCSS 8."

The break is **forward-only**: a *new* plugin on an *old* host fails. That is the reverse of the
direction we care about, and it reframes the entire case study. See §3 — the real lesson is not
"breaking your plugin contract is expensive," it is "**the expensive part was the version skew in
the middle layer, not the contract change at all.**"

### 0.5 REFUTED (for ESLint v9 specifically) — `context.getSourceCode()` was not removed in v9

The brief lists `context.getSourceCode()` → `context.sourceCode` among "which rule-context methods
were removed/replaced" in v9. `getSourceCode()`, `getFilename()`, `getPhysicalFilename()`, and
`getCwd()` were **deprecated in v9 and removed in v10.0.0** (2026-02-06). Zero occurrences of
`getSourceCode`, `getCwd`, `getFilename`, or `getPhysicalFilename` appear in the v9 migration guide
— VERIFIED by exhaustive grep of
<https://raw.githubusercontent.com/eslint/eslint/main/docs/src/use/migrate-to-9.0.0.md>; they appear
instead in
<https://raw.githubusercontent.com/eslint/eslint/main/docs/src/use/migrate-to-10.0.0.md>.

ESLint stated the *rule* for the split, and it is the most transferable sentence in the whole survey
— VERIFIED `[EXACT]`,
<https://eslint.org/blog/2023/09/preparing-custom-rules-eslint-v9/>:

> "We are deprecating the methods in favor of the properties (added in v8.40.0). These methods will
> be removed in **v10.0.0 (not v9.0.0)** as they are not blocking language plugins work."

**The discriminator is whether the old form blocks the host's own evolution.** Accessors whose
replacement needed a changed signature or a different host object (`getScope()` →
`sourceCode.getScope(node)`) were cut at v9 because they blocked the language-plugins
re-architecture. Accessors with a drop-in property equivalent (`getCwd()` → `cwd`) were carried a
whole extra major — 33 months — because carrying them cost nothing. See §4.6.

---

## 1. ROLLUP — the hook object form (union of old shape and richer new shape)

Sources: <https://rollupjs.org/plugin-development/>, raw at
<https://raw.githubusercontent.com/rollup/rollup/master/docs/plugin-development/index.md>;
type source <https://raw.githubusercontent.com/rollup/rollup/master/src/rollup/types.d.ts>;
dispatcher <https://raw.githubusercontent.com/rollup/rollup/master/src/utils/PluginDriver.ts>;
changelogs <https://raw.githubusercontent.com/rollup/rollup/master/CHANGELOG-2.md> and
<https://raw.githubusercontent.com/rollup/rollup/master/CHANGELOG.md>.

### 1.1 Which version, and — decisively — which *kind* of version

VERIFIED `[EXACT]` — `CHANGELOG-2.md`:

```
## 2.78.0

_2022-08-14_

### Features

- Support writing plugin hooks as objects with a "handler" property (#4600)
- Allow changing execution order per plugin hook (#4600)
- Add flag to execute plugins in async parallel hooks sequentially (#4600)

### Pull Requests

- [#4600](https://github.com/rollup/rollup/pull/4600): Allow using objects as hooks to change execution order ( @lukastaegert)
```

**Rollup 2.78.0, 2022-08-14, PR #4600 — a MINOR release.** This is the single most important fact
about the exhibit. The widening was additive and shipped without a major bump, which is only
possible because the old shape stayed valid. Contrast every other exhibit in this document, where
the equivalent change consumed a major.

### 1.2 The function form is still supported — verified three ways

1. **In the type**, as the left arm of a union. VERIFIED `[EXACT]`, `types.d.ts` line 578:

   ```ts
   export type ObjectHook<T, O = {}> = T | ({ handler: T; order?: 'pre' | 'post' | null } & O);
   ```

2. **In the docs**, as the default the object form is an alternative *to*. VERIFIED `[EXACT]`,
   `docs/plugin-development/index.md`:

   > "Instead of a function, hooks can also be objects. In that case, the actual hook function (or
   > value for `banner/footer/intro/outro`) must be specified as `handler`. This allows you to
   > provide additional optional properties that change hook execution or skip hook execution"

3. **In the dispatcher**, as a runtime ternary. VERIFIED `[EXACT]`, `PluginDriver.ts` — the same
   line appears at **two** call sites (331 in `runHook`, 414 in `runHookSync`):

   ```ts
   const handler = typeof hook === 'object' ? hook.handler : hook;
   ```

### 1.3 The technique, named precisely

**Structurally-discriminated union of the old shape and a richer new shape, where the old shape is
the payload of the new one.** `ObjectHook<T, O>` is the general form: `T` (the old value) union
`{ handler: T } & O` (the old value, boxed, plus extensions `O`).

Three properties make it work, and all three are transferable:

1. **The discriminant is a type test, not a tag field.** `typeof hook === 'object'` — no
   `{ kind: 'object' }` marker was needed, because a function and an object are disjoint at runtime.
   The old shape needed no retrofit to become distinguishable, which is exactly why no existing
   plugin had to change.
2. **The new shape is a strict superset in capability and a strict container of the old value.** The
   normalization is total and lossless: every object form reduces to a handler plus metadata; every
   function form is a handler with default metadata.
3. **`O` is an open extension slot, parameterized per hook.** VERIFIED `[EXACT]`, `types.d.ts`
   lines 589–593:

   ```ts
   export type PluginHooks = {
       [K in keyof FunctionPluginHooks]: ObjectHook<
           K extends AsyncPluginHooks ? MakeAsync<FunctionPluginHooks[K]> : FunctionPluginHooks[K],
           HookFilterExtension<K> & (K extends ParallelPluginHooks ? { sequential?: boolean } : {})
       >;
   };
   ```

   Note what this means: `sequential` is **not** available on every hook, only on
   `ParallelPluginHooks`. The brief's flat `{ order, handler, sequential }` is imprecise —
   `order` and `handler` are universal, `sequential` is parallel-hooks-only, `filter` is
   `resolveId`/`load`/`transform`-only. The union is *per-hook shaped*.

### 1.4 The extension slot demonstrably PAID OFF — a third capability landed 2.5 years later

This is the strongest single piece of evidence in the document that the union technique is worth its
cost, and it was not in the brief.

VERIFIED `[EXACT]` — `CHANGELOG.md`:

```
## 4.38.0

_2025-03-29_

### Features

- Support `.filter` option in `resolveId`, `load` and `transform` hooks (#5882)
```

**Rollup 4.38.0, 2025-03-29, PR #5882 — again a MINOR release.** A brand-new capability (declarative
`id`/`code` filters that let the host skip invoking the hook entirely) was added into the *same
object slot* opened in 2.78.0, **two years and seven months later**, with no break and no major bump.

INFERENCE: the object form's real return was not `order` and `sequential`. It was that Rollup bought
a **permanent, additive extension point on every hook** for the one-time cost of a two-shape
normalization. The 2022 change paid for the 2025 change. A design that had spent a major version on
`order` as a new positional argument would have had to spend another one on `filter`.

### 1.5 What Rollup did when it genuinely needed to widen a hook's ARGUMENTS

Since §0.1 refutes the framing, it is worth recording what Rollup actually does for the real problem.
It does **not** add positional parameters. It widens a trailing **options object** in the final
positional slot. VERIFIED `[EXACT]`, `docs/plugin-development/index.md` §`resolveId`:

```typescript
type ResolveIdHook = (
	source: string,
	importer: string | undefined,
	options: {
		importerAttributes: Record<string, string> | undefined;
		attributes: Record<string, string>;
		custom?: { [plugin: string]: any };
		isEntry: boolean;
	}
) => ResolveIdResult;
```

Two positional identity arguments (`source`, `importer`) plus one extensible options object holding
four members — note `importerAttributes`, which the brief's shorthand omits.

**That object demonstrably grew, in a minor.** VERIFIED `[EXACT]`, `CHANGELOG-2.md` — under
`## 2.58.0` / `_2021-10-01_`:

> `[#4230](https://github.com/rollup/rollup/pull/4230): Add isEntry flag to resolveId and this.resolve (@lukastaegert)`

UNVERIFIED: I did not establish when `attributes`, `custom`, or `importerAttributes` were each added
— `importerAttributes` produced no hit in the v4 changelog. The claim below rests on the one
verified instance, `isEntry`, which is sufficient for it.

INFERENCE: this is the same hybrid shape Node uses (§2.6) — **positional for the identity arguments,
one extensible object for everything the host may later want to say** — and Rollup, like Node, added
a field to that object in a minor release without touching any signature. Two of the six exhibits
converged on the shape independently, and both then exercised its extension point.

### 1.6 The COST, measured

The brief asks for the cost, and it is real but smaller than expected.

**Cost 1 — every consumer must normalize two shapes.** VERIFIED by exhaustive grep of
`PluginDriver.ts`: `typeof hook === 'object'` appears at **four** sites (331, 333, 414, 441). Two
are the handler extraction, one is the filter check, one is the sort. The normalization is *not*
centralized into a single `normalizeHook()` — it is repeated inline at each dispatch path.

**Cost 2 — a second place where validation must happen.** VERIFIED `[EXACT]`, `PluginDriver.ts`
`getSortedValidatedPlugins`:

```ts
	for (const plugin of plugins) {
		const hook = plugin[hookName];
		if (hook) {
			if (typeof hook === 'object') {
				validateHandler(hook.handler, hookName, plugin);
				if (hook.order === 'pre') {
					pre.push(plugin);
					continue;
				}
				if (hook.order === 'post') {
					post.push(plugin);
					continue;
				}
```

Note that `validateHandler` is only called on the object arm — the function arm's validity is
implied by `typeof`. The two arms have *asymmetric* validation, which is a maintenance hazard the
type system does not catch.

**Cost 3 — the type is materially harder to read.** `ObjectHook<T, O>` composed through
`HookFilterExtension<K>` and a conditional `ParallelPluginHooks` check is four type-level
indirections to answer "what may I put in `plugin.transform`?"

INFERENCE on the balance: Cost 1 is bounded and one-time (four sites, in one file, in the host).
Cost 3 is real and recurring for readers. Cost 2 is the sneaky one. Against that, §1.4 shows the
technique absorbing a second unplanned capability with zero further cost. **For a host with a
central dispatcher, the union is a good trade. For a contract with dispatch scattered across many
call sites, Cost 1 multiplies and the trade inverts.**

---

## 2. NODE.JS MODULE CUSTOMIZATION HOOKS — consolidation, chaining, and the hybrid shape

Sources: <https://raw.githubusercontent.com/nodejs/node/main/doc/api/module.md> (the markdown source
carries per-API YAML `added:`/`changes:` history blocks — this is the authoritative version table);
changelogs `CHANGELOG_V14.md`, `CHANGELOG_V16.md`, `CHANGELOG_V18.md` under
<https://raw.githubusercontent.com/nodejs/node/main/doc/changelogs/>; and the v16.12.0 loader source
at <https://raw.githubusercontent.com/nodejs/node/v16.12.0/lib/internal/modules/esm/loader.js>.

### 2.1 The consolidation: which version, and it was a MINOR

VERIFIED `[EXACT]` — the YAML history block on the `## Customization Hooks` section of `module.md`:

```yaml
  - version: v16.12.0
    pr-url: https://github.com/nodejs/node/pull/37468
    description: Removed `getFormat`, `getSource`, `transformSource`, and
                 `globalPreload`; added `load` hook and `getGlobalPreload` hook.
```

**Node v16.12.0, 2021-10-20, PR #37468.**

**Upstream doc error, caught against primary source — flag when citing this YAML.** The entry above
says `globalPreload` was *removed* and `getGlobalPreload` *added*. That is backwards for v16.12.0.
Both the v16 changelog (*"For consistency, `getGlobalPreloadCode` has been renamed to
`globalPreload`"*, §2.2) and the shipped v16.12.0 source (`globalPreload ??= getGlobalPreloadCode`
with a warning that `getGlobalPreloadCode` *"has been renamed to `globalPreload`"*, §2.3) agree that
**`globalPreload` is the NEW name and `getGlobalPreloadCode` the old one.** The changelog and the
executable source win over the API-doc YAML. (`globalPreload` was later itself replaced by
`initialize` in v20.6.0 — §2.4 — which may be how the YAML came to read as it does.)

The consolidation shipped as **SEMVER-MINOR** — VERIFIED `[EXACT]`, `CHANGELOG_V16.md`:

> `**(SEMVER-MINOR)** **esm**: consolidate ESM loader hooks (Jacob Smith) [#37468](https://github.com/nodejs/node/pull/37468)`

Removing four hooks in a *minor* of a soon-to-be-LTS release line is only defensible because the
whole surface was **Stability 1 – Experimental**. That is the decisive contextual fact, and it is
the same fact that governs our own small-N case (§9.5).

### 2.2 There WAS a documented migration table — printed in the release notes

The brief asks: "compatibility shim, hard break, or documented migration table?" The answer is **all
three, layered**, and the migration table is the tersest artifact in the survey. VERIFIED `[EXACT]`,
`CHANGELOG_V16.md`, the v16.12.0 "Notable Changes" section in full:

> #### Experimental ESM Loader Hooks API
>
> Node.js ESM Loader hooks have been consolidated to represent the steps involved needed to facilitate future loader chaining:
>
> 1. `resolve`: `resolve` \[+ `getFormat`]
> 2. `load`: `getFormat` + `getSource` + `transformSource`
>
> For consistency, `getGlobalPreloadCode` has been renamed to `globalPreload`.
>
> A loader exporting obsolete hook(s) will trigger a single deprecation warning (per loader) listing the errant hooks.

Two lines of table is the entire migration guide. It works because it is expressed as an *equation
over the old names* — a reader who knows the old contract can mechanically derive the new one.

### 2.3 The compatibility posture: functionally a hard break, ergonomically a named diagnostic

VERIFIED `[EXACT]` — the actual v16.12.0 implementation,
`lib/internal/modules/esm/loader.js`:

```js
  static pluckHooks({
    globalPreload,
    resolve,
    load,
    // obsolete hooks:
    dynamicInstantiate,
    getFormat,
    getGlobalPreloadCode,
    getSource,
    transformSource,
  }) {
    const obsoleteHooks = [];
    const acceptedHooks = ObjectCreate(null);

    if (getGlobalPreloadCode) {
      globalPreload ??= getGlobalPreloadCode;

      process.emitWarning(
        'Loader hook "getGlobalPreloadCode" has been renamed to "globalPreload"'
      );
    }
    if (dynamicInstantiate) ArrayPrototypePush(
      obsoleteHooks,
      'dynamicInstantiate'
    );
    if (getFormat) ArrayPrototypePush(
      obsoleteHooks,
      'getFormat',
    );
    if (getSource) ArrayPrototypePush(
      obsoleteHooks,
      'getSource',
    );
    if (transformSource) ArrayPrototypePush(
      obsoleteHooks,
      'transformSource',
    );

    if (obsoleteHooks.length) process.emitWarning(
      `Obsolete loader hook(s) supplied and will be ignored: ${
        ArrayPrototypeJoin(obsoleteHooks, ', ')
      }`,
      'DeprecationWarning',
    );
```

This one function is the richest artifact in the document. Read what it does:

- **Two different compatibility policies, chosen per hook.** `getGlobalPreloadCode` → `globalPreload`
  was a pure *rename*, so it got a **working alias** (`globalPreload ??= getGlobalPreloadCode`) plus
  a warning: old code keeps functioning. The four semantic changes got **"supplied and will be
  ignored"**: old code stops functioning, but says so by name.
- **The old hooks are still named in the host's signature.** `pluckHooks` destructures
  `dynamicInstantiate`, `getFormat`, `getGlobalPreloadCode`, `getSource`, `transformSource` — hooks
  that no longer exist — *purely to detect and report them*. `dynamicInstantiate` had been gone
  since Node 14 (§0.3) and is still listed here, a full major line later.
- **The destructuring IS the mechanism.** The host declares its entire known surface — live and
  obsolete — in one parameter pattern. That is what makes "name the errant hooks" possible at all.
  A host that did `if (plugin.load)` scattered across call sites could not produce this diagnostic.

INFERENCE, and this is the design payload: **the cost of removing a hook is not paid by keeping it
working. It is paid by keeping its NAME.** A one-line entry in the host's destructuring pattern, plus
a warning, converts "mysterious silent no-op" into "here is exactly what you supplied that I ignored."
That is ~90% of the migration benefit for ~2% of a compatibility shim's cost.

### 2.4 `register()`, `registerHooks()`, and `initialize` — verified versions

All VERIFIED `[EXACT]` from the YAML blocks in `module.md`:

| API | `added` | Notes |
| --- | --- | --- |
| `module.register(specifier[, parentURL][, options])` | `v20.6.0`, `v18.19.0` | **Now deprecated**: `deprecated: v25.9.0, v24.15.0`; runtime deprecation **DEP0205** in `v26.0.0` (PR #62401) |
| `module.registerHooks(options)` | `v23.5.0`, `v22.15.0` | Stability **1.2 – Release candidate** as of `v25.4.0`/`v24.13.1` (PR #60960) |
| `initialize()` | `v20.6.0`, `v18.19.0` | "Added `initialize` hook to replace `globalPreload`" |

Two observations the brief did not anticipate:

1. **`initialize` is itself a replacement**, not an original. `globalPreload` (which had *just*
   replaced `getGlobalPreloadCode` in v16.12.0) was replaced by `initialize` in v20.6.0. Three names
   for adjacent responsibilities in four years. INFERENCE: the hook that is hardest to get right is
   the *lifecycle/setup* hook, because its contract is "whatever the plugin needs before it starts,"
   which is exactly the requirement that keeps changing.
2. **`register()` is on its way out.** The async, separate-thread registration path is deprecated in
   favor of the synchronous in-thread `registerHooks()`. `module.md` states the preference —
   VERIFIED `[EXACT]`:

   > "The asynchronous hooks incur extra overhead from inter-thread communication, and have
   > [several caveats][] especially when customizing CommonJS modules in the module graph. In most
   > cases, it's recommended to use synchronous hooks via `module.registerHooks()` for simplicity."

   INFERENCE: this is a *whole registration mechanism* being retired and replaced while the **hook
   signatures themselves stayed identical** — `resolve(specifier, context, nextResolve)` and
   `load(url, context, nextLoad)` are documented identically under both. Node kept the expensive
   thing (the contract adapters implement) stable while replacing the cheap thing (how they get
   registered). That is a deliberate and copyable separation.

### 2.5 The signatures — VERIFIED exactly as the brief states

VERIFIED `[EXACT]` from the section headings in `module.md`, which appear **twice each**, once for
sync and once for async, with identical parameter lists:

- `#### Synchronous resolve(specifier, context, nextResolve)` (line 873)
- `#### Synchronous load(url, context, nextLoad)` (line 961)
- `#### Asynchronous resolve(specifier, context, nextResolve)` (line 1382)
- `#### Asynchronous load(url, context, nextLoad)` (line 1474)

And the `context` object's members, VERIFIED `[EXACT]`:

```
* `specifier` {string}
* `context` {Object}
  * `conditions` {string\[]} Export conditions of the relevant `package.json`
  * `importAttributes` {Object} An object whose key-value pairs represent the
    attributes for the module to import
  * `parentURL` {string|undefined} The module importing this one, or undefined
    if this is the Node.js entry point
* `nextResolve` {Function} The subsequent `resolve` hook in the chain, or the
  Node.js default `resolve` hook after the last user-supplied `resolve` hook
  * `specifier` {string}
  * `context` {Object|undefined} When omitted, the defaults are provided. When provided, defaults
    are merged in with preference to the provided properties.
```

### 2.6 Why the HYBRID shape works — the central finding for question A

Node did **not** go all-argument-object. It went: **positional identity arguments + one extensible
context object + one chaining function.** Here is why that specific arrangement is right, and each
reason is grounded in a verified fact above.

**Reason 1 — the positional slots are the arguments that can never grow.** `specifier` and `url` are
the *subject* of the call. There will never be a second specifier. Making them positional costs
nothing in evolvability because they have no evolution pressure, and it buys arity checking: omit
them and you have a bug the type system catches immediately (§7.1, probe4 — `TS2554: Expected 2
arguments, but got 1`).

**Reason 2 — the middle object is the only part under growth pressure, and it has grown.** VERIFIED
`[EXACT]`, the YAML history on the async `resolve` hook:

```yaml
  - version:
    - v21.0.0
    - v20.10.0
    - v18.19.0
    pr-url: https://github.com/nodejs/node/pull/50140
    description: The property `context.importAssertions` is replaced with
                 `context.importAttributes`. Using the old name is still
                 supported and will emit an experimental warning.
  - version:
    - v17.1.0
    - v16.14.0
    pr-url: https://github.com/nodejs/node/pull/40250
    description: Add support for import assertions.
```

Two context-object changes, both landed in **minors**, both **backported to three release lines**,
and the second — a *rename of a field* — kept the old name working with a warning. The extensible
object absorbed both a field addition and a field rename with zero signature churn.

**Reason 3 — the direction of flow is what makes it safe, and this is the axis the
argument-object-vs-positional framing misses entirely.** The `context` object flows **host → plugin**.
Widening it is safe *because plugins ignore fields they do not read*. There is no way for a new field
to break an existing hook. The dangerous direction is **plugin → host**: a bag the plugin fills and
the host reads, where a misspelled or omitted field is a silent behavioral change. Node's shape puts
the growing object on the safe side of the boundary. See §7.4 — this generalizes into the sharpest
rule the survey produced.

**Reason 4 — the chaining argument makes the contract's *own* extension composable.** VERIFIED
`[EXACT]`, `module.md`:

> "Hook functions nest: each one must always return a plain object, and chaining happens as a result
> of each function calling `next<hookName>()`, which is a reference to the subsequent loader's hook
> (in LIFO order)."

> "A hook that returns a value lacking a required property triggers an exception. A hook that returns
> without calling `next<hookName>()` _and_ without returning `shortCircuit: true` also triggers an
> exception. These errors are to help prevent unintentional breaks in the chain. Return
> `shortCircuit: true` from a hook to signal that the chain is intentionally ending at your hook."

What passing the next hook in as an argument buys, concretely:

- **The default implementation is always in reach, and is always the *current* default.** A hook that
  wants to handle one case and defer the rest writes `return nextResolve(specifier, context)`. When
  Node's default behavior changes, that hook inherits the change for free. Compare a plugin that
  reimplements the default: it is frozen at the version it was written against.
- **The forwarding call is where the context object's growth is absorbed.** VERIFIED `[EXACT]`
  (quoted in §2.5): `context` on `nextResolve` is `{Object|undefined}` — *"When omitted, the defaults
  are provided. When provided, defaults are merged in with preference to the provided properties."*
  A hook written before a new context field existed forwards the `context` it received, or omits it,
  and the merge fills the gap. **The chaining argument is what makes host→plugin object widening
  survive a forwarding hop.** Without it, every hook would have to reconstruct the full context and
  would drop unknown fields.
- **It turns "add a required capability" into "the chain already has one."** Any capability the host
  can implement itself is available to every plugin as `next*()`, so it never needs to be a *required*
  method on the plugin. This is the strongest structural answer to question C, and §2.7 shows Node
  using it.

### 2.7 Node ADDING A REQUIRED THING to an existing contract — the `shortCircuit` precedent

This is the closest exhibit in the survey to "add a required member to a live contract," and it is
worth stating precisely.

VERIFIED `[EXACT]`, YAML history on the async `resolve` hook:

```yaml
  - version:
    - v18.6.0
    - v16.17.0
    pr-url: https://github.com/nodejs/node/pull/42623
    description: Add support for chaining resolve hooks. Each hook must either
      call `nextResolve()` or include a `shortCircuit` property set to `true`
      in its return.
```

And the release note — VERIFIED `[EXACT]`, `CHANGELOG_V18.md`, v18.6.0, 2022-07-13:

> #### Experimental ESM Loader Hooks API
>
> Node.js ESM Loader hooks now support multiple custom loaders, and composition is achieved via
> "chaining": `foo-loader` calls `bar-loader` calls `qux-loader` (a custom loader _must_ now signal
> a short circuit when intentionally not calling the next).

Shipped **SEMVER-MINOR** (`**(SEMVER-MINOR)** **esm**: add chaining to loaders`, PR #42623).

Anatomy of the change, because every element is a deliberate choice:

- **A new obligation was added to every existing hook** — either call `next*()` or return
  `shortCircuit: true`. Existing hooks that did neither now throw.
- **It is enforced as an EXCEPTION, not a default.** Node explicitly refused to pick a default
  ("assume they meant to short-circuit" or "assume they meant to chain"), because both defaults are
  wrong some of the time and wrong *silently*. The docs state the reasoning: *"These errors are to
  help prevent unintentional breaks in the chain."*
- **The obligation is discharged by DATA in the return value**, not by implementing a method. The
  plugin does not gain a required method; it gains a required *field in a value it already
  returned*. That is a far cheaper obligation to add — no new function, no new signature.
- **It was affordable because the surface was experimental.** Same governing fact as §2.1.

INFERENCE: when a plugin system must add a required capability, **requiring a field in an
already-returned value is dramatically cheaper than requiring a new method**, and choosing a loud
exception over a silent default is correct precisely when both candidate defaults would be wrong
some of the time. Both moves are directly applicable to our contract.

---

## 3. POSTCSS 8 — the case study, correctly read

Sources: <https://raw.githubusercontent.com/postcss/postcss/main/lib/processor.js>,
`.../main/lib/lazy-result.js`, `.../main/lib/postcss.d.ts`, `.../main/CHANGELOG.md`,
`.../main/docs/guidelines/plugin.md`, `.../8.0.0/lib/postcss.js`,
`.../7.0.33/lib/processor.es6`, `.../7.0.35/lib/processor.es6`;
<https://github.com/postcss/postcss/wiki/PostCSS-8-for-end-users>;
<https://github.com/postcss/postcss/releases/tag/8.0.0>; npm registry.

§0.4 already refuted the exhibit's framing. This section establishes what actually happened and what
it actually cost, because the *real* story is more useful than the assumed one.

### 3.1 The `postcssPlugin` marker: the docs undersell it as diagnostics; it is the discriminator

The official guideline states only the diagnostic purpose — VERIFIED `[EXACT]`,
<https://raw.githubusercontent.com/postcss/postcss/main/docs/guidelines/plugin.md>:

```
### 1.5. Set `plugin.postcssPlugin` with plugin name

Plugin name will be used in error messages and warnings.
```

But the runtime uses it as the **type discriminator**. VERIFIED `[EXACT]`, `lib/processor.js`
`normalize()`, complete:

```js
  normalize(plugins) {
    let normalized = []
    for (let i of plugins) {
      if (i.postcss === true) {
        i = i()
      } else if (i.postcss) {
        i = i.postcss
      }

      if (typeof i === 'object' && Array.isArray(i.plugins)) {
        normalized = normalized.concat(i.plugins)
      } else if (typeof i === 'object' && i.postcssPlugin) {
        normalized.push(i)
      } else if (typeof i === 'function') {
        normalized.push(i)
      } else if (typeof i === 'object' && (i.parse || i.stringify)) {
        if (process.env.NODE_ENV !== 'production') {
          throw new Error(
            'PostCSS syntaxes cannot be used as plugins. Instead, please use ' +
              'one of the syntax/parser/stringifier options as outlined ' +
              'in your PostCSS runner documentation.'
          )
        }
      } else {
        throw new Error(i + ' is not a PostCSS plugin')
      }
    }
    return normalized
  }
```

Five-arm dispatch: creator (`postcss === true`) → unwrap (`postcss` truthy) → processor
(`Array.isArray(plugins)`) → **v8 visitor object (`typeof === 'object' && postcssPlugin`)** → **v7
function (`typeof === 'function'`)** → syntax error → not-a-plugin error.

The provenance is the interesting part. VERIFIED `[EXACT]`, PostCSS 7.0.36,
<https://raw.githubusercontent.com/postcss/postcss/7.0.36/lib/postcss.es6>:

```js
postcss.plugin = function plugin (name, initializer) {
  function creator (...args) {
    let transformer = initializer(...args)
    transformer.postcssPlugin = name
    transformer.postcssVersion = (new Processor()).version
    return transformer
  }
```

In v7 `postcssPlugin` was a **diagnostic label stamped onto a function**. In v8 the same identifier
became the **structural discriminator on an object**.

INFERENCE — and this is a genuinely useful, transferable observation: *a name field introduced for
diagnostics becomes the cheapest available discriminator when the contract later needs to distinguish
two shapes, because every existing participant already sets it.* PostCSS got its v7/v8 discriminator
for free, four years early, by having required a name for error messages. That is an argument for
putting an identity field on our adapters now even though nothing branches on it today.

### 3.2 The visitor form — the brief's enumeration is incomplete

VERIFIED `[EXACT]` from the `Processors` interface in
<https://raw.githubusercontent.com/postcss/postcss/main/lib/postcss.d.ts>, the full member list:
`AtRule`, `AtRuleExit`, `Comment`, `CommentExit`, `Declaration`, `DeclarationExit`, **`Document`**,
**`DocumentExit`**, `Once`, `OnceExit`, `Root`, `RootExit`, `Rule`, `RuleExit`. The brief omitted
`Document`/`DocumentExit` (used by syntaxes such as `postcss-html`).

The filter-object form is narrower than commonly assumed — only four members accept it. VERIFIED
`[EXACT]`:

```ts
  AtRule?: { [name: string]: AtRuleProcessor } | AtRuleProcessor
  AtRuleExit?: { [name: string]: AtRuleProcessor } | AtRuleProcessor
  Declaration?: { [prop: string]: DeclarationProcessor } | DeclarationProcessor
  DeclarationExit?:
    | { [prop: string]: DeclarationProcessor }
    | DeclarationProcessor
```

Note this is *the same union-of-two-shapes technique as Rollup's* (§1.3), applied per-member rather
than per-hook.

**And it is not the only place PostCSS uses it.** `normalize()`'s five-arm dispatch (§3.1) is the
*same* technique applied to the v7-vs-v8 plugin distinction itself: function (old shape) union
object-with-`postcssPlugin` (new shape), discriminated structurally by `typeof`, exactly as Rollup
discriminates a hook function from a hook object. INFERENCE: that makes **three exhibits converging
independently on structurally-discriminated unions** — Rollup's `ObjectHook`, PostCSS's visitor
filter-object form, and PostCSS's own plugin-generation dispatch — and PostCSS's is the only one that
carried a contract across a **major version intact**, six years and counting (§3.2, where the type
surface still exports both generations). It is the clearest demonstration of why the technique earns
its cost when participants are published independently, and, by the same logic, why §9.5 concludes we
should skip it in-repo.

The contract type itself, and — importantly — **the legacy type is still exported alongside it**.
VERIFIED `[EXACT]`, same file:

```ts
  export interface Plugin extends Processors {
    postcssPlugin: string
    prepare?: (result: Result) => Processors
  }

  export interface PluginCreator<PluginOptions> {
    (opts?: PluginOptions): Plugin | Processor
    postcss: true
  }

  export interface Transformer extends TransformCallback {
    postcssPlugin: string
    postcssVersion: string
  }

  export interface TransformCallback {
    (root: Root, result: Result): Promise<void> | void
  }
```

with `AcceptedPlugin` the union of both eras. **The type system carries both generations
simultaneously and permanently.** That is the type-level cost of the "keep the old shape working"
choice, and it is a cost PostCSS is still paying six years on.

### 3.3 PostCSS 8's own compatibility layer: a deprecation shim that still ships

VERIFIED `[EXACT]`, <https://raw.githubusercontent.com/postcss/postcss/8.0.0/lib/postcss.js>:

```js
postcss.plugin = function plugin (name, initializer) {
  if (console && console.warn) {
    console.warn(
      'postcss.plugin was deprecated. Migration guide:\n' +
        'https://evilmartians.com/chronicles/postcss-8-plugin-migration'
    )
  }
```

The v7 authoring helper was **kept and warned**, not removed. By 8.4.0 it prefixes the plugin name
and adds a locale branch — VERIFIED `[EXACT]`, `.../8.4.0/lib/postcss.js`, the warning becomes
`name + ': postcss.plugin was deprecated. Migration guide:\n' + …` with a `process.env.LANG`-gated
Chinese variant.

INFERENCE: note the refinement direction. The *first* version of the deprecation message did not say
**which** plugin was at fault; a later patch added the name. This is the same lesson as Node's
`pluckHooks` (§2.3) learned the hard way: **a deprecation warning that does not name the offending
participant is nearly useless in a system where the user did not write the participant.**

### 3.4 The `requires PostCSS 8` error — in the OLD major, shipped within 24 hours

The load-bearing correction. VERIFIED `[EXACT]`,
<https://raw.githubusercontent.com/postcss/postcss/main/CHANGELOG.md>:

```
## 7.0.33
- Add error message for PostCSS 8 plugins.
```
```
## 7.0.35
- Add migration guide link to PostCSS 8 error text.
```

Dates from the npm registry `time` field: postcss **8.0.0** published `2020-09-15T15:20:21.522Z`;
**7.0.33** published `2020-09-16T22:12:14.400Z` — **one day later**. 7.0.35 followed on
`2020-09-28T21:42:40.998Z`, 13 days after 8.0.0.

VERIFIED `[EXACT]`, <https://raw.githubusercontent.com/postcss/postcss/7.0.33/lib/processor.es6>
(lines 117-120 and 138-141):

```js
      if (i.postcss === true) {
        let plugin = i()
        throw new Error(
          'PostCSS plugin ' + plugin.postcssPlugin +
          ' requires PostCSS 8. Update PostCSS or downgrade this plugin.'
        )
      }
```
```js
      } else if (typeof i === 'object' && i.postcssPlugin) {
        throw new Error(
          'PostCSS plugin ' + i.postcssPlugin +
          ' requires PostCSS 8. Update PostCSS or downgrade this plugin.'
        )
      } else {
        throw new Error(i + ' is not a PostCSS plugin')
      }
```

and reworded at 7.0.35 to point at the guide:

```js
        throw new Error(
          'PostCSS plugin ' + plugin.postcssPlugin + ' requires PostCSS 8.\n' +
          'Migration guide for end-users:\n' +
          'https://github.com/postcss/postcss/wiki/PostCSS-8-for-end-users'
        )
```

INFERENCE — the transferable move, which no other exhibit in the survey performs: **when you ship a
new contract shape, patch the PREVIOUS version of the host to RECOGNIZE and REJECT the new shape by
name.** The old host cannot support the new plugin, but it can stop producing a nonsense error. The
prerequisite is exactly §3.1's discriminator — you can only detect the new shape if it is
structurally identifiable.

### 3.5 What it actually cost — measured, not asserted

The plugin API redesign is **not listed under "Breaking Changes"** in the 8.0.0 release notes at all
— VERIFIED `[EXACT]`, <https://github.com/postcss/postcss/releases/tag/8.0.0>, whose Breaking Changes
section covers only Node.js version drops, un-Babeled ES6+ sources, and `postcss.vendor` removal.
The plugin change is framed as a feature, with an acknowledgement:

> "The biggest change in PostCSS 8 is a new plugin API… **We know that rewriting old plugins will
> take time**, but the new API will improve the end-user's experience and make life easier for plugin
> developers: With new API, all plugins can share a single scan of the CSS tree. It makes CSS
> processing up to **20% faster**. Because npm often duplicates dependencies, you may have many
> `postcss` duplicates in your `node_modules`. New API fixes this problem."

And the CHANGELOG entry — VERIFIED `[EXACT]`:

```
## 8.0 "President Ose"
- Removed support for Node.js 6.x, 8.x, 11.x, and 13.x versions.
- Removed `postcss.vendor` helpers.
- Deprecated `postcss.plugin()` API.
- Plugins and runners must have `postcss` in `peerDependencies`.
- Prohibited to extend PostCSS AST classes.
- Added visitor API for plugins (by Alexey Bondarenko).
```

**The issue wave, with real durations** (VERIFIED via the GitHub Search API; a title search for
`"requires PostCSS 8"` in the window 2020-09-01..2021-12-31 returns **65 issues**). Durations
computed from `created_at`/`closed_at`:

| Issue | Opened | Closed | Open for |
| --- | --- | --- | --- |
| <https://github.com/nuxt/nuxt/issues/8087> "PostCSS 8" | 2020-09-17 | 2022-04-12 | **573 d** |
| <https://github.com/csstools/postcss-preset-env/issues/191> "Support PostCSS 8" | 2020-09-15 (release day) | 2021-11-16 | **427 d** |
| <https://github.com/facebook/create-react-app/issues/9664> "PostCSS 8" | 2020-09-17 | 2021-06-22 | **278 d** |
| <https://github.com/stylelint/stylelint/issues/4942> "Migrate to PostCSS 8" | 2020-09-15 | 2021-06-07 | **265 d** |
| <https://github.com/postcss/postcss-import/issues/435> | 2020-10-22 | 2021-03-31 | **160 d** |
| <https://github.com/parcel-bundler/parcel/issues/5160> | 2020-09-18 | 2020-12-30 | **103 d** |
| <https://github.com/facebook/create-react-app/pull/9716> "Update to PostCSS 8" (authored by `ai`, PostCSS's own maintainer) | 2020-09-28 | 2020-12-08 | **70 d — closed UNMERGED**, 321 👍 |

**`@tailwindcss/postcss7-compat`** — VERIFIED via <https://registry.npmjs.org/@tailwindcss%2Fpostcss7-compat>:
25 versions (2.0.1 → 2.2.17), first publish `2020-11-19T16:05:08Z`, last `2021-10-13T17:15:38Z` — a
**328-day lifespan**. `dependencies.postcss: "^7"`. Its `deprecated` field is `undefined` — it was
abandoned, never formally npm-deprecated.

Tailwind's own docs on why it existed — VERIFIED `[EXACT]`, <https://v2.tailwindcss.com/docs/installation>:

> "As of v2.0, Tailwind CSS depends on PostCSS 8. Because PostCSS 8 is only a few months old, many
> other tools in the ecosystem haven't updated yet… To help bridge the gap until everyone has
> updated, we also publish a PostCSS 7 compatibility build as `@tailwindcss/postcss7-compat` on npm…
> The compatibility build is identical to the main build in every way, so you aren't missing out on
> any features or anything like that."

**The long tail, dated** (npm registry `time` + `dependencies`):

| Milestone | Date | Δ from 8.0.0 |
| --- | --- | --- |
| postcss 8.0.0 | 2020-09-15 | — |
| postcss 7.0.33 (error added to the OLD major) | 2020-09-16 | **1 day** |
| `postcss-loader@4.0.3` first to accept v8 | 2020-10-02 | 17 d |
| tailwindcss v2.0.0 requires postcss ^8.0.9 | 2020-11-18 | 64 d |
| `@tailwindcss/postcss7-compat` first publish | 2020-11-19 | 65 d |
| PostCSS 7 support officially ended | 2021-01-01 | ~108 d |
| `react-scripts@4.0.3` — **still** on `postcss-loader: "3.0.0"` (v7) | 2021-02-22 | 160 d |
| `react-scripts@5.0.0` finally ships `postcss: "^8.4.4"` | 2021-12-14 | **455 days** |
| Sitnik: "PostCSS 8 migration was no ended" | 2022-05-25 | **617 days** |

### 3.6 The maintainer's own retrospective — no regret found, but a chilling effect

VERIFIED `[EXACT]`, `ai` (Andrey Sitnik) on <https://github.com/postcss/postcss/issues/1574>,
2021-05-10:

> "Nope. I supported PostCSS 7 for a 6 month after PostCSS 8 support. The support was ended at
> January 1, 2021. Only commercial support is possible right now."

> "@dezfowler update these libraries to PostCSS 8. It is unfair to ask me to work more, because
> somebody else (CRA, for instance) want to work less and ignored PRs with PostCSS update. BTW,
> `postcss-preset-env` 7→8 migration was not a blocker for CRA to update. They have a year to find a
> solution."

And, twenty months on — VERIFIED `[EXACT]`, <https://github.com/postcss/postcss/issues/1752>,
2022-05-25:

> "But we can think about removing them in next major release (**which will not be soon, since
> PostCSS 8 migration was no ended**)."

UNVERIFIED: **no statement of regret about the 8.0 API redesign itself was found.** Searches run
included `repo:postcss/postcss author:ai "PostCSS 8" in:body`,
`repo:postcss/postcss "PostCSS 8" migration in:comments commenter:ai`, and
`org:postcss "PostCSS 9" in:title`. The nearest thing to a retrospective is the *deterrent* quoted
above: the transition's cost is cited as a reason **not to attempt another major**, not as a mistake.

### 3.7 What the corrected PostCSS story actually teaches

INFERENCE, and it differs sharply from the brief's assumption:

1. **The contract change was not the expensive part.** PostCSS 8 ran v7 plugins from day one. The
   expensive part was the **middle layer** — `postcss-loader`, `react-scripts`, Nuxt, Parcel, CRA —
   which pinned an old *host* and therefore rejected new *plugins*. 455 days of pain caused by
   version skew in runners, not by an incompatible plugin API.
2. **Therefore the risk to model is not "will my adapters break." It is "who else pins my host."**
   With zero external plugin authors and zero external runners (§9.5), this entire failure mode is
   absent from our situation.
3. **Forward-only breaks are the hazardous kind.** Old-plugin-on-new-host was fine. It was
   new-plugin-on-old-host that exploded — and the only mitigation is the one PostCSS shipped within
   24 hours: teach the old host to *name* the new shape it cannot run.
4. **Cost that a design doc should price in:** the type surface permanently carries both
   generations (§3.2); the deprecation shim is still in the shipped source six years on (§3.3); and
   the maintainer's stated position is that another major is off the table indefinitely (§3.6).
   **The real cost of a breaking contract change is not the migration — it is the loss of appetite
   for the next one.**

---

## 4. ESLINT v9 (and v10) — the deprecation runway, the compat shim, and schema-as-data

Sources: <https://raw.githubusercontent.com/eslint/eslint/main/docs/src/use/migrate-to-9.0.0.md>,
`.../migrate-to-10.0.0.md`, `.../docs/src/extend/custom-rules.md`, `.../docs/src/extend/plugins.md`,
`.../CHANGELOG.md`; <https://eslint.org/blog/2023/09/preparing-custom-rules-eslint-v9/>;
<https://eslint.org/version-support/>;
<https://raw.githubusercontent.com/eslint/rewrite/main/packages/compat/README.md> and
`.../packages/compat/src/fixup-rules.js`.

§0.5 already corrected the v9/v10 split. This section covers what the brief actually asked.

### 4.1 What v9 removed — the signature-changing group

VERIFIED `[EXACT]`, `migrate-to-9.0.0.md`. v9 removed ~22 `context` methods with drop-in
`SourceCode` equivalents (`getSource` → `getText`, `getAllComments`, all the token accessors,
`parserServices`, `getDeclaredVariables`), plus these three, which the guide separates out because
they **required different method signatures**:

| Removed on `context` | Replacement on `SourceCode` |
| --- | --- |
| `context.getAncestors()` | `sourceCode.getAncestors(node)` |
| `context.getScope()` | `sourceCode.getScope(node)` |
| `context.markVariableAsUsed(name)` | `sourceCode.markVariableAsUsed(name, node)` |

Changelog: `feat!: Remove deprecated context methods (#17698)` under `v9.0.0 - April 5, 2024`.

Note the shape of the change: **the new forms take the node explicitly.** The old forms read it from
implicit traversal state on the host. INFERENCE: the migration is from *ambient/implicit* context to
*explicit parameter passing* — the same direction Node took with `nextResolve`, and the same
direction the argument-object question is really about. Explicitness is what unblocked ESLint's
language-plugins rearchitecture, per its own stated motive:

VERIFIED `[EXACT]`, the 2023 blog:

> "These changes are necessary as part of the work to implement language plugins, which gives ESLint
> first-class support for linting languages other than JavaScript. … Going forward, `context` is the
> home for functionality that rules need to interact with the core while `SourceCode` is the home for
> functionality that rules need to interact with the code being linted."

### 4.2 The deprecation runway — measured

All version→date mappings VERIFIED from release headers in
<https://raw.githubusercontent.com/eslint/eslint/main/CHANGELOG.md>. Intervals are INFERENCE
(arithmetic over verified dates).

| New form | Added | Deprecation notice | Removed | Runway |
| --- | --- | --- | --- | --- |
| `SourceCode#getScope(node)` | v8.37.0 — 2023-03-28 | blog 2023-09-26 | v9.0.0 — 2024-04-05 | **≈12.3 mo** |
| `SourceCode#getAncestors(node)`, `#getDeclaredVariables(node)` | v8.38.0 — 2023-04-07 | blog 2023-09-26 | v9.0.0 — 2024-04-05 | **≈12.0 mo** |
| `SourceCode#markVariableAsUsed(name, node)` | v8.39.0 — 2023-04-21 | blog 2023-09-26 | v9.0.0 — 2024-04-05 | **≈11.5 mo** |
| `context.sourceCode` (+ `cwd`/`filename`/`physicalFilename`) | v8.40.0 — 2023-05-05 | blog 2023-09-26 | **v10.0.0 — 2026-02-06** | **≈33.1 mo** |

Derived: formal notice → v9 removal ≈ **6.3 months**; v9 deprecation → v10 removal ≈ **22.1 months**.

**The three-phase pattern is the reusable artifact:**
**(1) ship the new form in a minor → (2) announce deprecation with a straddle idiom → (3) remove in a
major.** Phase 1 lands ~6–12 months before phase 2. Nothing is ever removed in the same release it
was deprecated.

The blog's own recommended straddle idiom — VERIFIED `[EXACT]`:

> `const sourceCode = context.sourceCode ?? context.getSourceCode();`
> `const scope = sourceCode.getScope ? sourceCode.getScope(node) : context.getScope();`

**Feature detection on the member. Never a version check.** This recurs in every exhibit (§8.3).

### 4.3 `@eslint/compat` — what it actually covers

**Direction — the brief's question answered directly.** VERIFIED `[EXACT]`, README:

> "This package contains functions that allow you to wrap existing ESLint rules, plugins, and
> configurations that were **intended for use with ESLint v8.x or v9.x** to allow them to **work
> as-is in ESLint v9.x and v10.x**."

**OLD artifact on NEW host.** Not the reverse. `peerDependencies: {"eslint": "^8.40 || 9 || 10"}`
(<https://registry.npmjs.org/@eslint/compat>).

**Exports** — VERIFIED `[EXACT]`, README: `fixupRule(rule)`, `fixupPluginRules(plugin)`,
`fixupConfigRules(configs)`, and `includeIgnoreFile(path)` (now itself deprecated in favour of
`@eslint/config-helpers`).

**What it re-adds is a CLOSED 20-ENTRY MAP** — VERIFIED `[EXACT]`, `fixup-rules.js`:

```js
const removedMethodNames = new Map([
	["getSource", "getText"],
	["getSourceLines", "getLines"],
	["getAllComments", "getAllComments"],
	["getDeclaredVariables", "getDeclaredVariables"],
	["getNodeByRangeIndex", "getNodeByRangeIndex"],
	["getCommentsBefore", "getCommentsBefore"],
	// … through …
	["getTokensBetween", "getTokensBetween"],
]);
```

plus the three signature-changing ones, reconstructed by tracking traversal state:

```js
		let currentNode = compatSourceCode.ast;

		const compatContext = Object.assign(Object.create(context), {
			parserServices: compatSourceCode.parserServices,
			/*
			 * The following methods rely on the current node in the traversal,
			 * so we need to add them manually.
			 */
			getScope() { return compatSourceCode.getScope(currentNode); },
			getAncestors() { return compatSourceCode.getAncestors(currentNode); },
			markVariableAsUsed(variable) { compatSourceCode.markVariableAsUsed(variable, currentNode); },
		});
```

**What it does NOT cover.** README's entire stated limitation set is two sentences — VERIFIED
`[EXACT]`:

> "**Note:** All plugins are not guaranteed to work in ESLint v9.x or v10.x. This package fixes the
> most common issues but can't fix everything."

VERIFIED-BY-DERIVATION (set-difference of `removedMethodNames` against the v9 migration guide's
breaking-change list; the comparison is mine, both inputs are primary): not covered are
`context.getComments()` (in the removal table, absent from the map), `sourceCode.getComments()`,
`CodePath#currentSegments`, the code-path precalculation semantics change, `meta.schema` now being
required, and the `RuleTester` tightening.

**Two facts that matter more than the coverage list:**

1. **It shipped ~33 days AFTER v9.0.0 GA.** First publish `1.0.1` on `2024-05-08T14:48:36.948Z`
   (there is no published `1.0.0`) versus v9.0.0 on 2024-04-05 — VERIFIED via
   <https://registry.npmjs.org/@eslint/compat>. The official escape hatch was not ready at the break.
2. **It infers the host major by DUCK TYPING, because no contract version exists to read.** This is
   the capstone finding of the whole survey. VERIFIED `[EXACT]`, `fixup-rules.js`:

   ```js
   	function ruleCreate(context) {
   		const sourceCode = context.sourceCode;

   		// No need to create old methods for ESLint < 9
   		if ("getScope" in context) {
   			return originalCreate(context);
   		}

   		let eslintVersion = 9;
   		if (!("getCwd" in context)) {
   			eslintVersion = 10;
   		}
   ```

   ESLint's **own official compatibility package** reconstructs the host's major version from the
   presence of two individual members. It computes a variable literally named `eslintVersion` from
   feature probes. See §8.

### 4.4 `meta.schema` — declaring options as DATA, and the v9 default flip

VERIFIED `[EXACT]`, `custom-rules.md`:

> "Rules with options must specify a `meta.schema` property, which is a [JSON Schema] format
> description of a rule's options which will be used by ESLint to validate configuration options and
> prevent invalid or unexpected inputs before they are passed to the rule in `context.options`."

**The v9 flip — the brief's belief is correct.** VERIFIED `[EXACT]`, the v8.57.0-tagged docs
(<https://raw.githubusercontent.com/eslint/eslint/v8.57.0/docs/src/extend/custom-rules.md>) warning
v8 users what is coming:

> "Note: **Prior to ESLint v9.0.0, rules without a schema are passed their options directly from the
> config without any validation.** In ESLint v9.0.0 and later, **rules without schemas will throw
> errors when options are passed.** See the [Require schemas and object-style rules] RFC for further
> details."

And the migration guide — VERIFIED `[EXACT]`, `migrate-to-9.0.0.md`:

> ## `meta.schema` is required for rules with options
>
> As of ESLint v9.0.0, an error will be thrown if any options are passed to a rule that doesn't
> specify `meta.schema` property.
>
> **To address:**
> - If your rule expects options, set `meta.schema` property to a JSON Schema format description…
> - If your rule doesn't expect any options, there is no action required…
> - **(not recommended)** you can also set `meta.schema` to `false` to disable this validation…

Governing RFC: <https://github.com/eslint/rfcs/blob/main/designs/2021-schema-object-rules/README.md>
— "Require schemas and object-style rules". The same RFC drove dropping function-style rules;
schema-required and object-rules-required were **one design decision** landed together.

Two details worth carrying:

- **`false` is a third state**, distinct from absent and `[]`. Absent/`[]` ⇒ no options permitted;
  `false` ⇒ validation off, arbitrary options passed through. An explicit, documented opt-out seam
  inside a tightened contract.
- **A deliberately FROZEN sub-contract inside an evolving one** — VERIFIED `[EXACT]`,
  `custom-rules.md`:

  > "At present, it is explicitly planned to not update schema support beyond this level due to
  > ecosystem compatibility concerns."

  (Schema support is pinned at JSON Schema Draft-04.) INFERENCE: ESLint chose to freeze the *data
  language* precisely so the contract expressed in it could keep evolving. A validator's version is
  itself a contract surface, and pinning it is a legitimate move.

### 4.5 `meta.defaultOptions` — version VERIFIED, and it is an ADDITIVE MINOR

**v9.15.0, November 15, 2024.** VERIFIED `[EXACT]`, CHANGELOG:

> `v9.15.0 - November 15, 2024`
> `feat: add meta.defaultOptions (#17656) (Josh Goldberg ✨)`

Negative control: `grep -c defaultOptions` against the **v9.0.0**-tagged `custom-rules.md` returns
**0** — it did not exist at v9.0.0. So this is a contract extension shipped **7.3 months into the v9
line, in a minor**.

Merge semantics — VERIFIED `[EXACT]` from the v9.15.0-tagged docs (byte-identical to current `main`
apart from markdown formatting):

> Rules may specify a `meta.defaultOptions` array of default values for any options. When the rule is
> enabled in a user configuration, ESLint will **recursively merge** any user-provided option elements
> on top of the default elements.
>
> **Each element of the options array is merged according to the following rules:**
>
> * Any missing value or explicit user-provided `undefined` will fall back to a default option
> * User-provided arrays and primitive values other than `undefined` override a default option
> * User-provided objects will merge into a default option object and replace a non-object default otherwise
>
> Option defaults will also be validated against the rule's `meta.schema`.

So: **per-index over the options array; deep for objects; replace for arrays and primitives;
explicit `undefined` counts as absent.**

### 4.6 Why schema/defaults AS DATA aids evolution — the brief's question, answered

INFERENCE across the verified facts above. Four distinct mechanisms, and only the first is obvious:

1. **The host can validate before dispatch.** A code-expressed default (`const opt = options.x ?? 5`)
   runs *inside* the rule, so a typo in the user's config reaches the rule as a silent `undefined`.
   A schema rejects it at config load, naming the rule. The error moves from late-and-silent to
   early-and-attributed — the identical failure mode question A is about (§7).
2. **The host can add capabilities that read the declaration without touching any rule.** Because
   `schema` is data, ESLint could later ship `defaultOptions` merging, Ajv `useDefaults` interplay,
   and config-level validation, all reading a field rules had already declared for a different
   reason. Data declarations accumulate consumers; code does not.
3. **The default becomes part of the published contract.** `meta.defaultOptions` is inspectable by
   `--print-config`, documentation generators, and editors. A `??` buried in a rule body is
   discoverable only by reading the source. This is exactly sibling `b-optional-and-capabilities.md`'s
   "the absent-property default must live at the contract, not in the caller."
4. **Adding the declaration is a strictly additive minor** (§4.5), whereas changing behavior encoded
   in code is a behavioral change with no declaration site to diff.

**Cost, stated honestly:** the data language becomes a contract surface of its own, and ESLint had to
**freeze it at Draft-04 forever** to stop it evolving underneath everyone (§4.4). You are trading a
code-versioning problem for a schema-versioning problem — a good trade only when the data language is
small enough to freeze.

### 4.7 ESLint's N and N−1 policy — the only explicit one found in the survey

VERIFIED `[EXACT]`, <https://eslint.org/version-support/>:

> "The ESLint team provides ongoing support for the current version and **six months of limited
> support for the previous version**."
>
> "Major ESLint release lines move through a status of Current, to Maintenance, to End of Life (EOL).
> A release line is considered **Current when prerelease work begins**. At that point, the previous
> release line moves to **Maintenance** status and stays there until **six months after the general
> availability of the Current release line**."
>
> "**Maintenance** - Receives critical bug fixes, including security issues, and **compatibility fixes
> to ensure interoperability between major release lines**."

Two details that make this stronger than it first reads:

- **"Maintenance" explicitly funds the N/N−1 bridge**, not merely security. Interoperability between
  majors is a named, budgeted deliverable.
- **The clock starts at PRERELEASE, not GA.** v9 entered Maintenance on 2025-11-14 (v10.0.0-alpha.0)
  and reached EOL 2026-08-06 — six months after v10 GA (2026-02-06). Observed v8→v9 overlap was
  identical: v8 EOL 2024-10-05, exactly six months after v9 GA 2024-04-05.

### 4.8 Plugin `meta` — declared, but NOT branched on

VERIFIED `[EXACT]`, <https://raw.githubusercontent.com/eslint/eslint/main/docs/src/extend/plugins.md>:

> "For easier **debugging and more effective caching** of plugins, it's recommended to provide a
> `name`, `version`, and `namespace` in a `meta` object at the root of your plugin"

ESLint states the purpose as debugging and caching — **not compatibility gating** — and the source
agrees. VERIFIED (negative, by shallow clone of `eslint/eslint` at `main` = 10.8.1 and tag v9.39.5):
searching all of `lib/` for `semver`, `supportedVersions`, `apiVersion`, `contractVersion`,
`satisfies(` returns **zero hits**; `semver` appears **0 times in all of `lib/`**.

The three-part precise answer:

- **`meta.name`/`meta.version` — diagnostic + serialization.** One read site, `getObjectId()` in
  `lib/config/config.js`, feeding `toJSON()` and `--print-config`.
- **`meta.version` IS load-bearing for CACHE IDENTITY** — it flows into
  `lib/cli-engine/lint-result-cache.js`'s `hashOfConfigFor`, so bumping it invalidates `--cache`.
  But that is **string equality, not version comparison**. ESLint never asks "is this supported."
- **`meta.namespace` IS genuinely behavior-branching** — the one plugin-meta key that changes host
  behavior, widening the names a rule's `meta.languages` entries may match (`lib/config/config.js`).

INFERENCE: even the exhibit with the most mature versioning discipline in the survey has **no
contract-version field the host branches on.** Its rule-level `meta` reads are all *capability flags*
— `meta.fixable`, `meta.hasSuggestions`, `meta.schema`, `meta.languages` — never a version.

---

## 5. BABEL `api.assertVersion()` — the inversion

Sources: <https://babeljs.io/docs/config-files#apiassertversionrange>, raw at
<https://raw.githubusercontent.com/babel/website/main/docs/config-files.md>;
<https://raw.githubusercontent.com/babel/babel/7.x/packages/babel-core/src/config/helpers/config-api.ts>;
<https://raw.githubusercontent.com/babel/babel/7.x/packages/babel-helper-plugin-utils/src/index.ts>;
<https://raw.githubusercontent.com/babel/website/main/docs/helper-plugin-utils.md>;
<https://github.com/babel/babel/pull/7450>.

### 5.1 Documented usage and accepted argument forms

VERIFIED `[EXACT]`, `docs/config-files.md`:

> ### `api.assertVersion(range)`
>
> While `api.version` can be useful in general, it's sometimes nice to just declare your version.
> This API exposes a simple way to do that with:
>
> ```js
> module.exports = function(api) {
>   api.assertVersion("^7.2");
>   return { /* ... */ };
> };
> ```

The docs show only the range string; the implementation accepts **`string | number`**. Range strings
were supported **from first ship** — there was never a number-only phase, VERIFIED from the
introducing PR's diff (<https://patch-diff.githubusercontent.com/raw/babel/babel/pull/7450.diff>),
which introduces `function assertVersion(range: string | number)` with the `semver.satisfies` call in
the original implementation.

UNVERIFIED: "first shipped in `@babel/core` 7.0.0-beta.41" is INFERENCE from the merge commit's
`package.json` (7.0.0-beta.40) plus the next npm publish date (2018-03-14), corroborated by the
shim's hardcoded `"^7.0.0-beta.41"`. **No CHANGELOG entry mentioning `assertVersion` or #7450 was
found.**

### 5.2 The implementation — it THROWS, with a structured error

VERIFIED `[EXACT]`, `config-api.ts` on the `7.x` branch (released Babel 7):

```ts
function assertVersion(range: string | number): void {
  if (typeof range === "number") {
    if (!Number.isInteger(range)) {
      throw new Error("Expected string or integer value.");
    }
    range = `^${range}.0.0-0`;
  }
  if (typeof range !== "string") {
    throw new Error("Expected string or integer value.");
  }

  // We want "*" to also allow any pre-release, but we do not pass
  // the includePrerelease option to semver.satisfies because we
  // do not want ^7.0.0 to match 8.0.0-alpha.1.
  if (range === "*" || semver.satisfies(coreVersion, range)) return;

  const message =
    `Requires Babel "${range}", but was loaded with "${coreVersion}". ` +
    `If you are sure you have a compatible version of @babel/core, ` +
    `it is likely that something in your build process is loading the ` +
    `wrong version. Inspect the stack trace of this error to look for ` +
    `the first entry that doesn't mention "@babel/core" or "babel-core" ` +
    `to see what is calling Babel.`;
  // …
  const limit = Error.stackTraceLimit;
  if (typeof limit === "number" && limit < 25) {
    // Bump up the limit if needed so that users are more likely
    // to be able to see what is calling Babel.
    Error.stackTraceLimit = 25;
  }
  const err = new Error(message);
  if (typeof limit === "number") { Error.stackTraceLimit = limit; }

  throw Object.assign(err, {
    code: "BABEL_VERSION_UNSUPPORTED",
    version: coreVersion,
    range,
  });
}
```

Three details worth copying wholesale:

- **The error carries structured fields** — `code`, `version` (actual), `range` (demanded) — not just
  a string. Machine-inspectable.
- **It temporarily raises `Error.stackTraceLimit` to 25** so the user can see *who* loaded the wrong
  host. The failure is almost never in the plugin or the host; it is in the resolution graph between
  them, and the diagnostic is designed for that.
- **`assertVersion` never warns.** The only non-throwing path is an explicit env escape hatch,
  `BABEL_7_TO_8_DANGEROUSLY_DISABLE_VERSION_CHECK`, which is the host's own 7→8 migration seam.

An **integer argument is more permissive than its string equivalent**: `7` becomes
`` `^${range}.0.0-0` `` (prerelease-inclusive), whereas a range string goes to `satisfies` *without*
`includePrerelease`. Not documented; read from the source.

### 5.3 What the inversion buys — confirmed verbatim by the introducing PR

The brief's hypothesis is confirmed by primary source. VERIFIED `[EXACT]`,
<https://github.com/babel/babel/pull/7450> body:

> This allows plugins to use `api.assertVersion(7)` as a general version, or any semver string to
> assert that the current version of Babel is one that is supported.
>
> Trying to load `@babel/preset-env` for instance with Babel 6's CLI results in
>
> ```
> Error: Requires Babel "^7.0.0-0", but was loaded with "6.26.0". …
> ```
>
> **where before it would throw about accessing `loose` on `undefined` or something along those
> lines because the `options` object isn't passed to plugins in Babel 6.x.**

And the design intent stated flatly — VERIFIED `[EXACT]`,
<https://raw.githubusercontent.com/babel/website/main/docs/helper-plugin-utils.md>:

> "This is not aiming to implement APIs that are missing on a given Babel version, but it is meant to
> provide **clear error messages if a plugin is run on a version of Babel that doesn't have the APIs
> that the plugin is trying to use.**"

> ### `api.assertVersion` always exists
>
> Babel 6 and early betas of Babel 7 do not have `assertVersion`, so this wrapper ensures that it
> exists and throws a useful error message when not supplied by Babel itself.

**The decisive argument for the inversion, in one sentence:** the plugin knows its own requirements at
authoring time; the host cannot, because plugins ship independently and *later*. And the shim proves
it — `@babel/helper-plugin-utils` lets a **new plugin produce a correct version error on an old
host that never heard of `assertVersion`.** Host-checks-plugin can never achieve that, because the old
host is precisely the party that would need updating.

VERIFIED `[EXACT]`, the shim's own fallback, which branches on the host version to give a *better*
message:

```ts
  let err;
  if (version.startsWith("7.")) {
    err = new Error(
      `Requires Babel "^7.0.0-beta.41", but was loaded with "${version}". ` +
        `You'll need to update your @babel/core version.`,
    );
  } else {
    err = new Error(`Requires Babel "${range}", but was loaded with "${version}". ` + /* … */);
  }
```

### 5.4 What it REQUIRES of the host

Four obligations, all VERIFIED from the source and shim above. This is the price of the inversion:

1. **The host must CALL the plugin's factory function** with an `api` argument. A plain-object plugin
   has nowhere to receive `api`. *The inversion is only available to function-shaped plugins.*
2. **The host must pass an object exposing an accurate `version`.** Even a host lacking
   `assertVersion` must expose `version`, since the shim reads `api.version` off it.
3. **The host must keep `version` honest.** A lying `version` silently defeats the whole contract.
4. **The `api` must be a real live object.** From `copyApiObject`'s comment: *"Babel >= 7 <= beta.41
   passed the API as a new object that had babel/core as the prototype. While slightly faster, it
   also means that the `Object.assign` copy below fails."*

### 5.5 The `api` surface, and what function-not-object buys

The types reveal a three-tier layering the docs page does not make explicit — VERIFIED `[EXACT]`,
`config-api.ts`:

```ts
export type ConfigAPI = {
  version: string;
  cache: SimpleCacheConfigurator;
  env: EnvFunction;
  async: () => boolean;
  assertVersion: typeof assertVersion;
  caller: CallerFactory;
};

export type PresetAPI = { targets: TargetsFunction; addExternalDependency: (ref: string) => void; } & ConfigAPI;
export type PluginAPI = { assumption: AssumptionFunction; } & PresetAPI;
```

Config files get the base; presets add `targets` and `addExternalDependency`; plugins add
`assumption`. **The capability set is scoped to the participant's role, by type composition.**

UNVERIFIED: `api.targets`, `api.assumption`, and `api.async` were not found documented in a ten-page
sample of `babel/website/docs/`; not all ~150 files were checked, so "undocumented" would overclaim.

A Babel plugin is a **function** `(api, options, dirname) => ({ visitor })` — VERIFIED `[EXACT]` from
`docs/helper-plugin-utils.md` (`declare((api, options, dirname) => {…})`) and the source type
`builder: (api: PluginAPI, options: Option, dirname: string) => PluginObject<…>`. UNVERIFIED:
babeljs.io's *plugin-development* page does not document the three-arg signature; the authoritative
in-docs statement is on the `helper-plugin-utils` page.

INFERENCE — what the function shape buys for evolution, and it is more than it appears:

- **It creates a CALL SITE, which is the only place a host can inject capabilities.** A plain object
  has no seam. This is the single structural difference between Babel's and PostCSS's/Rollup's
  plugin shapes, and it is why only Babel can do the inversion.
- **The plugin can negotiate BEFORE committing** — assert, or branch on `api.version` /
  `api.caller()` / `api.targets()` — and return a *different* plugin object per host. A static object
  is frozen at author time.
- **New `api` members are additive-safe**: `assumption` and `addExternalDependency` were added without
  breaking any plugin, because plugins read only what they know. *This is the host→plugin direction
  again* (§2.6, §7.4).
- **It gives a shim somewhere to stand.** `declare` wraps the factory, patches `api`, and forwards.
  Impossible with a plain object.

---

## 6. `fastify-plugin` — declared range, host-enforced gate

Sources: <https://raw.githubusercontent.com/fastify/fastify-plugin/main/README.md> and
`.../main/index.js`; <https://raw.githubusercontent.com/fastify/fastify/main/lib/plugin-utils.js>,
`.../lib/errors.js`, `.../lib/plugin-override.js`, `.../docs/Reference/Plugins.md`,
`.../docs/Reference/LTS.md`.

### 6.1 PREMISE CORRECTION — the file is `index.js`, and the check is not in fastify-plugin

REFUTED: `fastify-plugin/plugin.js` **does not exist** (404 on both `master` and `main`; the file is
`index.js`). More importantly, **the semver check is not in `fastify-plugin` at all.** `index.js`
only *stamps metadata*; the enforcement lives in `fastify` itself.

(`master` and `main` READMEs are byte-identical, verified by diff; `main` is the default branch.)

VERIFIED `[EXACT]`, `fastify-plugin/index.js` — its entire enforcement contribution is three lines:

```js
  fn[Symbol.for('skip-override')] = options.encapsulate !== true
  fn[Symbol.for('fastify.display-name')] = options.name
  fn[Symbol.for('plugin-meta')] = options
```

Its own throws are wrap-time *shape* validation, distinct from the host's semver gate:

```js
    throw new TypeError(`fastify-plugin expects a function, instead got a '${typeof fn}'`)
    throw new TypeError('The options object should be an object')
    throw new TypeError(`fastify-plugin expects a version string, instead got '${typeof options.fastify}'`)
```

INFERENCE: this split is itself the design lesson. **The plugin-side helper declares; the host
enforces.** A plugin-side check could be skipped by not using the helper; a host-side check cannot.
Contrast Babel (§5), where the plugin-side call *is* the check — and note that Babel's shim exists
precisely to compensate for that weakness.

### 6.2 The metadata shape

VERIFIED `[EXACT]`, README:

> `fastify-plugin` can do three things for you:
> - Add the `skip-override` hidden property
> - Check the bare-minimum version of Fastify
> - Pass some custom metadata of the plugin to Fastify

> #### Fastify version
> If you need to set a bare-minimum version of Fastify for your plugin, just add the [semver] range
> that you need:
> ```js
> module.exports = fp(function (fastify, opts, done) { /* … */ done() }, { fastify: '5.x' })
> ```

> #### Name
> Fastify uses this option to validate the dependency graph, allowing it to ensure that no name
> collisions occur and making it possible to perform dependency checks.

> #### Dependencies
> You can also check if the `plugins` and `decorators` that your plugin intend to use are present in
> the dependency graph.
> ```js
> module.exports = fp(plugin, {
>   fastify: '5.x',
>   decorators: { fastify: ['plugin1', 'plugin2'], reply: ['compress'] },
>   dependencies: ['plugin1-name', 'plugin2-name']
> })
> ```

### 6.3 The actual error, and where it lives

VERIFIED `[EXACT]`, `fastify/lib/plugin-utils.js`:

```js
function checkVersion (fn) {
  const meta = getMeta(fn)
  if (meta?.fastify == null) return

  const requiredVersion = meta.fastify

  const fastifyRc = rcRegex.test(this.version)
  if (fastifyRc === true && semver.gt(this.version, semver.coerce(requiredVersion)) === true) {
    // A Fastify release candidate phase is taking place. In order to reduce
    // the effort needed to test plugins with the RC, we allow plugins targeting
    // the prior Fastify release to be loaded.
    return
  }
  if (requiredVersion && semver.satisfies(this.version, requiredVersion, { includePrerelease: fastifyRc }) === false) {
    throw new FST_ERR_PLUGIN_VERSION_MISMATCH(meta.name, requiredVersion, this.version)
  }
}
```

The message template is **not at the throw site** — VERIFIED `[EXACT]`, `fastify/lib/errors.js`:

```js
  FST_ERR_PLUGIN_VERSION_MISMATCH: createError(
    'FST_ERR_PLUGIN_VERSION_MISMATCH',
    "fastify-plugin: %s - expected '%s' fastify version, '%s' is installed"
  ),
```

Rendered: `fastify-plugin: <name> - expected '<range>' fastify version, '<running>' is installed`,
code `FST_ERR_PLUGIN_VERSION_MISMATCH`. Note the trap for a reader: the message begins
`"fastify-plugin: "` but the throw comes from **fastify**.

Note also the **RC relaxation**: during fastify's own release-candidate phase the gate loosens so
plugins targeting the prior release still load. That is the host *widening its own gate* during its
own instability window — a nice, small, copyable idea.

### 6.4 `decorators` — a REQUIRED-CAPABILITY declaration checked BEFORE the plugin runs

This is the exhibit's most relevant contribution to question C. VERIFIED `[EXACT]`,
`lib/plugin-utils.js`:

```js
function registerPlugin (fn) {
  const pluginName = registerPluginName.call(this, fn) || getPluginName(fn)
  checkPluginHealthiness.call(this, fn, pluginName)
  checkVersion.call(this, fn)
  checkDecorators.call(this, fn)
  checkDependencies.call(this, fn)
  return shouldSkipOverride(fn)
}
```

and `registerPlugin` is invoked from the encapsulation override **before the plugin body executes** —
VERIFIED `[EXACT]`, `lib/plugin-override.js`:

```js
module.exports = function override (old, fn, opts) {
  const shouldSkipOverride = pluginUtils.registerPlugin.call(old, fn)
```

The check itself:

```js
function _checkDecorators (that, instance, decorators, name) {
  assert(Array.isArray(decorators), 'The decorators should be an array of strings')

  decorators.forEach(decorator => {
    const withPluginName = typeof name === 'string' ? ` required by '${name}'` : ''
    if (!checks[instance].call(that, decorator)) {
      throw new FST_ERR_PLUGIN_NOT_PRESENT_IN_INSTANCE(decorator, withPluginName, instance)
    }
  })
}
```

Error — VERIFIED `[EXACT]`, `lib/errors.js`:

```js
  FST_ERR_PLUGIN_NOT_PRESENT_IN_INSTANCE: createError(
    'FST_ERR_PLUGIN_NOT_PRESENT_IN_INSTANCE',
    "The decorator '%s'%s is not present in %s"
  ),
```

INFERENCE: `decorators` is **capability negotiation done as a static precondition, not a runtime
version check.** The plugin declares "I need these capabilities to exist" and the host verifies them
before invoking anything. It is strictly better than a version check for the same purpose: it says
what is actually needed rather than a proxy for it, it survives capabilities moving between versions,
and it fails at registration with a named cause. **This is the single most directly applicable idea
in the survey for a required-capability problem.**

### 6.5 Gate-only, verified by enumeration

VERIFIED (negative, by exhaustive grep of the fastify `main` tarball): `Symbol.for('plugin-meta')`
appears in **exactly one** non-test source location (`lib/plugin-utils.js:20`, inside `getMeta`);
`getMeta()` has **exactly four** call sites, all in `lib/plugin-utils.js`; `meta.fastify` is read at
**one** place, inside `checkVersion`.

**No consumer branches behavior on the declared version.** Metadata drives throw-or-pass three times
plus a name push for diagnostics. One nuance: `checkVersion` *does* branch (the `rcRegex` path) — but
on the **host's own** version, not on what the plugin declared.

### 6.6 Fastify's support policy

VERIFIED `[EXACT]`, <https://raw.githubusercontent.com/fastify/fastify/main/docs/Reference/LTS.md>:

> 1. Major releases […] are supported for a minimum period of six months from their release date.
> 2. Major releases will receive security updates for an additional six months from the release of
>    the next major release.
>
> > ## Security Releases and Semver
> > As a consequence of providing long-term support for major releases, there are occasions when
> > breaking changes must be released as a _minor_ version release.

And the docs' own statement of why `fastify-plugin` exists at all — VERIFIED `[EXACT]`,
`docs/Reference/Plugins.md`:

> "Using the `fastify-plugin` module is recommended, as it solves this problem and allows passing a
> version range of Fastify that the plugin will support… If not using `fastify-plugin`, the
> `'skip-override'` hidden property can be used, but it is not recommended. **Future Fastify API
> changes will be your responsibility to update, whilst `fastify-plugin` ensures backward
> compatibility.**"

UNVERIFIED/FLAG: `docs/Guides/Ecosystem.md` contains **no** version or support policy, contrary to
the brief's expectation. Also, `Plugins.md`'s example is stale — it still shows `fp(..., '0.x')`
against the README's `'5.x'`.

---

## 7. CROSS-CUTTING A — ARGUMENT-OBJECT vs POSITIONAL

The brief asks for authoritative support, the strongest counter-argument, and an honest assessment of
whether a JSDoc `@typedef` recovers the precision lost. **I settled this empirically rather than by
citation**, because the question is about what *this* toolchain actually does, and that is testable.

### 7.1 The experiment

**Method.** TypeScript **7.0.2** (`npm i typescript`, `tsc --version` → `Version 7.0.2`), Node
**v24.18.0**, plain ESM `.js` fixtures with JSDoc types, `--allowJs --checkJs --strict --noEmit
--module nodenext --target es2023`. Ran 2026-08-14. VERIFIED — every result below is executed
compiler output, not recall.

**Result 1 — a REQUIRED field's absence is caught REGARDLESS of literal freshness.**

```js
/**
 * @typedef {object} FetchArgs
 * @property {string} url
 * @property {number} timeoutMs
 */
/** @param {FetchArgs} args */ function fetchIt(args) {}

fetchIt({ url: 'a' });                       // (A) fresh literal
const argsB = { url: 'a' }; fetchIt(argsB);  // (B) via const — freshness GONE
const argsE = { url: 'a', timeoutMS: 1 }; fetchIt(argsE);  // (E) misspelled required field, via const
```

Compiler output:

```
probe1.js(12,9): error TS2741: Property 'timeoutMs' is missing in type '{ url: string; }' but required in type 'FetchArgs'.
probe1.js(16,9): error TS2741: Property 'timeoutMs' is missing in type '{ url: string; }' but required in type 'FetchArgs'.
probe1.js(27,9): error TS2741: Property 'timeoutMs' is missing in type '{ url: string; timeoutMS: number; }' but required in type 'FetchArgs'.
```

**All three error.** Missing-required-property is `TS2741`, an *assignability* failure — a different
mechanism from the excess-property check, and **entirely unaffected by literal freshness**. Case (E)
is the important one: a **typo in a required field is caught even through a `const`**, because the
typo manifests as a missing required property, not merely as an excess one.

**Result 2 — the established excess-property fact reproduces exactly.**

```
probe1.js(19,35): error TS2561: Object literal may only specify known properties, but 'timeout' does not exist in type 'FetchArgs'. Did you mean to write 'timeoutMs'?
```
…on the fresh literal; and the `const`-laundered equivalent (`argsD`) produced **no error**. Confirms
the brief's given fact, and confirms it is *scoped to excess properties only*.

**Result 3 — an all-optional bag is NOT fully untyped: TypeScript's WEAK TYPE DETECTION catches
zero-overlap.**

```js
/** @typedef {object} OptBag @property {string} [url] @property {number} [timeoutMs] */
const bagB = { timeoutMS: 1 }; fetchIt(bagB);   // via const, misspelled
```
```
probe2.js(16,9): error TS2559: Type '{ timeoutMS: number; }' has no properties in common with type 'OptBag'.
```

`TS2559` fires even through a `const`. A type whose properties are *all* optional is a "weak type,"
and assigning something sharing **no** properties with it is an error. So the counter-argument's
strong form — "an all-optional bag is effectively untyped" — is **partially REFUTED**.

**Result 4 — but the hole is real, and it is PARTIAL OVERLAP.**

```js
const bagA = { url: 'a', timeoutMS: 1 };   fetchIt(bagA);      // OptBag  — NO ERROR
const mixedA = { url: 'a', timeoutMS: 1 }; fetchMixed(mixedA); // MixedBag (url required) — NO ERROR
```

**Neither errors.** One correct property satisfies weak-type detection, and the `const` defeats
excess-property checking. **A typo in an OPTIONAL field, passed through any variable, is silent** —
and adding a required field to the type does not close it. This is precisely the "field silently
`undefined`, late or never" failure the brief names, and it is confirmed.

**Result 5 — `@satisfies` (TS 4.9+, and it works in JSDoc) RECOVERS the check on a named const.**

```js
/** @satisfies {OptBag} */
const sat = { url: 'a', timeoutMS: 1 };
/** @satisfies {Adapter} */
const adapter = { start: () => {}, stpo: () => {} };
```
```
probe5.js(32,25): error TS2561: Object literal may only specify known properties, but 'timeoutMS' does not exist in type 'OptBag'. Did you mean to write 'timeoutMs'?
probe5.js(46,36): error TS2353: Object literal may only specify known properties, and 'stpo' does not exist in type 'Adapter'.
```

**`@satisfies` on the declaration keeps excess-property checking alive without the value having to be
a fresh literal at the call site.** This is the remedy, and it applies directly to adapter objects.

**Result 6 — the handler side. Destructuring gives an argument object the arity check positional args
have.**

```js
/** @callback ObjHandler @param {Ctx} ctx */
/** @type {ObjHandler} */ const objH  = ({ url }) => {};        // subset      — NO ERROR
/** @type {ObjHandler} */ const objH2 = ({ url, nope }) => {};  // nonexistent
/** @callback PosHandler @param {string} url @param {number} t @param {string} n */
/** @type {PosHandler} */ const posH  = (url) => {};            // fewer       — NO ERROR
/** @type {PosHandler} */ const posH2 = (url,t,n,extra) => {};  // more
```
```
probe3.js(16,23): error TS2339: Property 'nope' does not exist on type 'Ctx'.
probe3.js(22,7): error TS2322: Type '(url: any, t: any, n: any, extra: any) => void' is not assignable to type 'PosHandler'.
  Target signature provides too few arguments. Expected 4 or more, but got 3.
```

This is the finding that most changes the recommendation. The brief's given fact — "TS accepts a
function with FEWER parameters" — is confirmed for positional (`posH`, no error). But an argument
object is **not** worse here: destructuring a subset is fine (`objH`, no error, correct and desirable),
while destructuring a **name that does not exist** is `TS2339`. **Destructuring restores, on the
implementer's side, exactly the misspelling protection that positional parameters lose to name-free
binding.** A positional handler that names its second parameter `tiemout` gets no diagnostic at all;
an object handler that destructures `{ tiemout }` gets one.

**Result 7 — positional call sites do get arity checking, and the Node hybrid type-checks.**

```
probe4.js(5,1):  error TS2554: Expected 2 arguments, but got 1.
probe4.js(39,64): error TS2339: Property 'nope' does not exist on type 'ResolveContext'.
```
…while `/** @type {ResolveHook} */ const r1 = (specifier) => ({url: specifier});` — ignoring both
`context` and `nextResolve` — produced **no error**, confirming §2.6 Reason 1 and that Node's shape
is expressible and enforceable in JSDoc.

### 7.2 What the experiment settles

INFERENCE over Results 1–7. **The object-vs-positional axis is the wrong axis. The real variable is
REQUIREDNESS.**

| Property of the design | Precision retained? |
| --- | --- |
| Argument object, fields **required** | **Full.** Omission and misspelling both caught, freshness-independent (Result 1). |
| Argument object, fields **all optional** | **Partial.** Zero-overlap caught (Result 3); **partial-overlap typos silent** (Result 4). |
| Argument object + `@satisfies` at the producer | **Full**, even for optional fields (Result 5). |
| Handler destructuring the object | **Full** on names (Result 6) — *better* than positional. |
| Positional, required params | **Full arity** (Result 7); **zero name checking** on the implementer's side. |
| Positional, optional params | Same silent-`undefined` failure as an optional bag. |

So: **a JSDoc `@typedef` DOES recover the lost precision — conditionally.** It recovers it fully when
the fields are required, and when they are optional it recovers it only if the producer uses
`@satisfies` (or constructs the value as a fresh literal in an annotated position). The smell the
counter-argument correctly identifies is **optionality, not object-ness**. An all-optional bag is
vague; so is a positional signature with three trailing optional parameters. The bag is not worse —
it is merely a more comfortable place to *hide* optionality, which is a real ergonomic hazard even
though it is not a type-system one.

### 7.3 Authoritative support, and the strongest counter

**Support** is thin on the "options object" framing specifically, and strong on the *hybrid*. The
strongest support is behavioural, not prescriptive: **Node (§2.6) and Rollup (§1.5) independently
converged on positional identity args plus one extensible object**, and Node's context object then
absorbed a field addition and a field rename in minors, with backports (§2.6 Reason 2). The mechanism
is stated in the docs — VERIFIED `[EXACT]`, `module.md` on `nextResolve`'s `context`: *"When omitted,
the defaults are provided. When provided, defaults are merged in with preference to the provided
properties."*

The **strongest counter-argument** in the survey is not about typing at all — it is LSP's. LSP
*replaced a protocol-version handshake with a capability object*, and to make that safe it had to
write down an explicit forward-compatibility rule for the object. VERIFIED `[EXACT]`,
<https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/> (raw
source `_specifications/lsp/3.17/general/initialize.md`):

> "For future compatibility a `ClientCapabilities` object literal can have more properties set than
> currently defined. Servers receiving a `ClientCapabilities` object literal with unknown properties
> should ignore these properties. **A missing property should be interpreted as an absence of the
> capability.** If a missing property normally defines sub properties, all missing sub properties
> should be interpreted as an absence of the corresponding capability."

INFERENCE: read the counter-argument out of that. **An extensible object only works when
"absent" has a single, written-down, universally-agreed meaning.** LSP could adopt one because
"absent = capability not supported" is uniform across every field. If the fields of *our* argument
object would each need a *different* absent-semantics — one defaults to `true`, one to a computed
value, one is an error — then the object genuinely does make the contract vaguer, and the brief's
counter-argument holds. The test is not "how many fields" but "**is there one rule for absence?**"

**A system that regretted its choice:** none found for object-vs-positional. But LSP explicitly
retired the adjacent mechanism — VERIFIED `[EXACT]`, same source:

```typescript
	/**
	 * If the protocol version provided by the client can't be handled by
	 * the server.
	 *
	 * @deprecated This initialize error got replaced by client capabilities.
	 * There is no version handshake in version 3.0x
	 */
	export const unknownProtocolVersion: 1 = 1;
```

A protocol that *had* version negotiation, deprecated it, and replaced it with a capability object.
That is the closest thing to a documented regret in the survey, and it points **toward** the object.

### 7.4 The rule that actually falls out — DIRECTION OF FLOW

INFERENCE, and this is the sharpest thing the pass produced. It supersedes "prefer an options object":

> **An extensible object is safe in the HOST → PLUGIN direction and hazardous in the PLUGIN → HOST
> direction.**

- **Host → plugin** (Node's `context`, Babel's `api`, LSP's `capabilities`, ESLint's `context`): the
  host fills it, the plugin reads what it knows. Adding a field cannot break anyone, because ignoring
  an unknown field is the correct behavior and is the *default* behavior. Every exhibit that widened
  successfully in a minor widened in this direction.
- **Plugin → host** (a return value, a config bag, an options argument the adapter supplies): the
  plugin fills it and the host reads it. A misspelled or omitted field is a **silent behavioral
  change** — Result 4. This direction needs **required fields**, or `@satisfies` at the construction
  site, or an explicit fail-loud rule like Node's `shortCircuit` (§2.7).

Checked against the survey: **it holds in every exhibit.** Node's growing object is host→plugin
(§2.6); the one plugin→host obligation Node added, `shortCircuit`, was made a **throwing requirement**
rather than an optional field (§2.7). Rollup's object hook is plugin→host — and note Rollup made
`handler` **required** in that arm (`{ handler: T; order?: … }`), leaving only the metadata optional.
Neither system left a plugin→host bag all-optional.

---

## 8. CROSS-CUTTING B — CONTRACT VERSIONING

### 8.1 The count

Surveyed for an explicit contract version, across this document's six exhibits plus webpack, Vite,
Prettier, TypeScript LS plugins, VS Code, LSP, and npm itself.

**Plugin-declared, monotonic CONTRACT-version field: ZERO systems.** Not one. Not PostCSS (§3.7,
`postcssVersion` exists only on the *retired* v7 `Transformer` type and records the *host* version at
wrap time). Not ESLint (§4.8, verified negative across all of `lib/`). Not Rollup, Vite, Prettier, or
webpack's plugin API.

**What dominates instead:**

| Mechanism | Systems | Verdict |
| --- | --- | --- |
| **Host-package semver range declared by the plugin** (`peerDependencies`; `engines.vscode`) | PostCSS, ESLint, Rollup, Vite, Prettier, webpack, fastify, VS Code — **all of them** | **DOMINANT, universal.** |
| **Per-feature opt-in flags / feature detection** | Vite, VS Code, webpack, ESLint's own shim, the blog's straddle idiom | **The actual evolution mechanism.** |
| **Host provides ITS version, plugin may branch** | Rollup `this.meta.rollupVersion`, Vite `this.meta.viteVersion`, webpack `this.version`, Babel `api.version` | Present in 4; genuinely used in 3, always as gate or feature-check. |
| **Capability negotiation** | LSP; fastify's `decorators` | 2 — and LSP *deprecated its version handshake* to get here. |
| **Inject the contract instead of versioning it** | TypeScript LS plugins | 1 — sidesteps the question. |
| **Version selection in the DISTRIBUTION channel** | VS Code marketplace | 1 — the only true multi-version delivery. |
| **Explicit plugin-declared contract version** | **none** | **0.** |

### 8.2 Is the version field ever used for real behavior branching? The honest count

**Zero instances of "host does v1 things for v1 plugins, v2 things for v2 plugins."** Every real use
is a gate, a feature check, or a diagnostic:

- **webpack `this.version = 2`** is documented *for* branching — VERIFIED `[EXACT]`,
  <https://raw.githubusercontent.com/webpack/webpack.js.org/main/src/content/api/loaders.mdx>:
  *"**Loader API version.** Currently `2`. This is useful for providing backwards compatibility.
  Using the version you can specify custom logic or fallbacks for breaking changes."*
  It is a **hardcoded literal that has never incremented**: `version: 2,` appears identically in
  `lib/NormalModule.js` at **v2.7.0, webpack-4, and main** (VERIFIED at all three tags) — including
  across the 4→5 break. **A documented backward-compat branching field that carried zero information
  through the ecosystem's largest breaking change.** This is the strongest available evidence that
  contract-version fields do not get maintained.
- **Rollup plugins** use `this.meta.rollupVersion` as a **throw-gate**, deriving the range from their
  own `peerDependencies` — VERIFIED `[EXACT]`,
  <https://raw.githubusercontent.com/rollup/plugins/master/packages/node-resolve/src/index.js>:
  `validateVersion(this.meta.rollupVersion, peerDependencies.rollup);`
- **`@vitejs/plugin-legacy`** is the closest thing to branching in the survey, and it is a
  **feature-availability check with graceful degradation**, not contract dispatch — VERIFIED
  `[EXACT]`,
  <https://raw.githubusercontent.com/vitejs/vite/main/packages/plugin-legacy/src/index.ts>:
  ```ts
  const viteVersion = this.meta.viteVersion
  supportsLegacyOxcMinification = !!viteVersion && isVersionGte(viteVersion, legacyOxcMinificationSupportedVersion)
  ```
- **fastify** — gate-only, verified by enumeration (§6.5).
- **Babel `assertVersion`** — gate-only; throws (§5.2). `api.version` exists for branching but the
  docs position `assertVersion` as the ergonomic default.

**The universal substitute is duck typing.** ESLint's own compat package computes a variable named
`eslintVersion` from two `in` checks (§4.3). ESLint's deprecation blog tells rule authors
`context.sourceCode ?? context.getSourceCode()`. webpack's docs tell loader authors
`this.getLogger ? this.getLogger() : console` — VERIFIED `[EXACT]`, `api/loaders.mdx`. LSP's spec
mandates it. **Feature detection is what the ecosystem actually does, at every layer, in every
exhibit.**

### 8.3 Documented "N and N−1" policies

- **ESLint — YES, and it is the only real one.** §4.7: current + six months of limited support for
  the previous major, with "compatibility fixes to ensure interoperability between major release
  lines" named as a funded deliverable of Maintenance status.
- **Fastify — YES, but for the HOST package**: minimum six months per major, plus six months of
  security updates after the next major (§6.6). Says nothing about plugin compatibility.
- **Vite** — a support *window* exists (current minor, previous major's latest minor, second-to-last
  major's latest minor;
  <https://raw.githubusercontent.com/vitejs/vite/main/docs/releases.md>) but it is a fix-and-security
  window for the host package and **must not be cited as a plugin-contract policy**. Its actual
  plugin-facing commitment is the deprecation policy: *"Deprecated features will continue to work
  with a type or logged warning. They will be removed in the next major release after entering
  deprecated status."*
- **PostCSS — six months, stated retroactively in an issue comment**, not policy (§3.6).
- **webpack, Prettier, Rollup, TypeScript LS plugins — none found.**
- **VS Code — no prose policy, but a stronger mechanism.** The marketplace resolves an *older
  compatible extension version* for an older host. VERIFIED `[EXACT]`,
  <https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/platform/extensionManagement/common/extensionGalleryService.ts>:
  ```ts
  async getCompatibleExtension(extension, includePreRelease, targetPlatform, productVersion = …) {
    if (await this.isExtensionCompatible(extension, includePreRelease, targetPlatform)) { return extension; }
    …
    const result = await this.getExtensions([…], { compatible: true, productVersion, queryAllVersions: true, targetPlatform }, …);
    return result[0] ?? null;
  }
  ```
  INFERENCE: this achieves unbounded multi-version support **with no contract version and no host
  branching**, by moving version selection into the *distribution channel*. Worth naming because it
  shows the problem is often better solved outside the contract than inside it.

Where multi-major support exists in npm-land it is achieved **per-plugin by widening a peer range**,
undocumented as policy and inconsistent even within one project's own official plugins — VERIFIED via
the npm registry: `@vitejs/plugin-vue@6.0.8` declares `^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0` while
`@vitejs/plugin-react@6.0.5` declares `^8.0.0`.

### 8.4 The mechanism everyone actually relies on, and its stated theory

VERIFIED `[EXACT]`, npm's own docs
(<https://raw.githubusercontent.com/npm/documentation/main/content/cli/v10/configuring-npm/package-json.mdx>,
source of <https://docs.npmjs.com/cli/v10/configuring-npm/package-json#peerdependencies>):

> "In some cases, you want to express the compatibility of your package with a host tool or library,
> while not necessarily doing a `require` of this host. This is usually referred to as a _plugin_."
>
> "In npm versions 3 through 6, `peerDependencies` were not automatically installed… **As of npm v7,
> peerDependencies _are_ installed by default.**"
>
> "**Assuming the host complies with [semver], only changes in the host package's major version will
> break your plugin.** Thus, if you've worked with every 1.x version of the host package, use `"^1.0"`
> or `"1.x"` to express this."

That last sentence **is the ecosystem's theory of contract evolution**: *the contract version is the
host's major version.* No separate number, because a separate number is a second thing to keep
honest — and webpack's frozen `version: 2` is the empirical proof that the second number does not get
kept honest.

VERIFIED empirically on this machine (npm 11.16.0): an unsatisfied peer range is a **hard `ERESOLVE`
error**, not a warning — and it fails even when the peer is marked *optional*, because optionality
means "may be absent," not "may be the wrong version."

---

## 9. CROSS-CUTTING C — ADDING A REQUIRED METHOD

### 9.1 What actually happened, ranked by observed frequency

| Strategy | Observed in | Frequency |
| --- | --- | --- |
| **(i) Make it optional with a documented default** | Node (all hooks optional, §0.2); Rollup ("one or more of the properties"); ESLint (`meta.defaultOptions`, §4.5); PostCSS (`prepare?`); Vite (`perEnvironmentStartEndDuringDev` etc.) | **DOMINANT — near-universal.** |
| **(iii) Major bump + migration guide** | PostCSS 8 (§3); ESLint v9 and v10 (§4); webpack 4→5 | **Common, and the observed method for genuinely breaking changes.** |
| **(iv) Capability-flag negotiation** | fastify `decorators` (§6.4); LSP `capabilities` (§7.3); VS Code `enabledApiProposals` | **Rare but decisive where present.** |
| **(ii) Base/default-implementation object plugins spread in** | Not encountered in any exhibit — **but see the evidence caveat below** | Not observed |

**Strategy (ii) — the verdict rests on argument, not on the survey.** UNVERIFIED as a negative:
**none of my four research briefs asked about default-implementation base objects**, so "not
observed" here is absence of evidence from searches that were not looking for it. I am flagging this
rather than reporting a bolded zero, because the brief named it as one of four candidate techniques
and a flat refutation on unsearched ground would be exactly the kind of claim the task asks me to
flag.

What I *did* observe, incidentally and consistently, is the opposite arrangement: every surveyed
system puts the default in the **host**, not in the plugin. Node's `next*()` chain terminates in
*the Node default hook* (§2.6). Rollup's `null` return means "I decline, you handle it." ESLint's
`meta.defaultOptions` is merged **by the host** (§4.5).

INFERENCE, and this is what actually carries the recommendation — it is independent of the survey:
a spread-in base couples every plugin to a **snapshot of the defaults taken at authoring time**, so
improving a default requires every plugin to re-publish. That is the precise problem the technique
claims to solve, reintroduced one level down. A host-side default improves for everyone at once, and
is inspectable at one site. **Prefer a host-side default over a spread-in base — on that reasoning,
not on a claimed ecosystem consensus I did not search for.**

### 9.2 The strongest observed move for a genuinely new REQUIRED capability

Node's `shortCircuit` (§2.7) is the exhibit. Its anatomy generalizes to a recipe:

1. **Prefer a required FIELD IN AN ALREADY-RETURNED VALUE over a required METHOD.** A new method is a
   new function every adapter must author. A required field in a value they already return is a
   one-line change with an obvious site.
2. **Refuse to pick a default when both candidate defaults are silently wrong** — throw instead.
   Node's docs state the reasoning: *"These errors are to help prevent unintentional breaks in the
   chain."* A wrong-but-silent default is worse than a loud error precisely for the class of failure
   Result 4 (§7.1) demonstrates.
3. **Ship it in a minor if the surface is experimental**; that is what made it affordable.

The second-strongest is fastify's `decorators` (§6.4): the plugin **declares which capabilities it
needs**, and the host verifies them *before invoking anything*. This is strictly better than a version
check for the same purpose — it names what is actually required rather than a proxy for it, and it
fails at registration with an attributed cause.

### 9.3 When each strategy is right

INFERENCE across the exhibits:

- **(i) optional + host-side default** — right whenever the host *can* compute a sensible default.
  This is almost always, and it is why it dominates. The non-negotiable condition, from sibling
  `b-optional-and-capabilities.md` and confirmed by §4.6 here: the default must be stated **at the
  contract**, not buried in a caller's `??`.
- **(iii) major bump + migration guide** — right when the old shape *blocks the host's own evolution*
  (ESLint's stated criterion, §0.5) and only then. ESLint's own behavior is the model: it deferred
  every removal that did not block it, by 33 months.
- **(iv) capability negotiation** — right when the host must know the plugin's shape **before
  invoking it**, or when capabilities move between versions independently. fastify checks decorators
  before the plugin body runs; a post-hoc check would be too late.
- **(ii) spread-in base object** — **not right.** See §9.1.

### 9.4 The three-phase runway, if a break is unavoidable

Distilled from ESLint (§4.2), PostCSS (§3.3–3.4), and Node (§2.3) — all three independently used the
same shape:

1. **Ship the new form first, in a minor.** Both forms work. ESLint's gap: 11.5–33 months.
2. **Announce deprecation, and publish the straddle idiom** — the exact two-line `??` snippet, not
   just prose. Warn at runtime, and **name the offending participant** (PostCSS's 8.0.0 warning did
   not; a later patch added the name — §3.3; Node's `pluckHooks` names every errant hook — §2.3).
3. **Remove in a major.** And, if the break is forward-only, **patch the previous host version to
   recognize and reject the new shape by name** (PostCSS shipped this in 24 hours — §3.4).

### 9.5 Does having NO external consumers change the answer? — the decisive contextual fact

Our case: **2–3 first-party adapters, all in the same repo, no external plugin authors.**

**What it changes — and it is a lot:**

1. **Strategy (iii) becomes nearly free, and therefore the DEFAULT.** Every measured cost in §3.5 —
   455 days to `react-scripts@5.0.0`, a 328-day parallel compat package, 65 issues, a maintainer's
   permanent loss of appetite for another major — is a *coordination* cost across independently-versioned
   publishers. With one repo and one commit, the migration is a refactor. **Change the contract and
   fix all three adapters in the same commit.** This inverts the usual ranking: (iii) dominates
   in-repo, where (i) dominates in public.
2. **The entire deprecation runway collapses.** Two-form periods, straddle idioms, `@eslint/compat`,
   `@tailwindcss/postcss7-compat`, `postcss.plugin()`'s six-year-old warning — every one exists to buy
   time for people you cannot deploy atomically with. You can. **Do not build a runway.**
3. **Version gates lose their purpose entirely.** `assertVersion`, `peerDependencies`, `engines.vscode`,
   `FST_ERR_PLUGIN_VERSION_MISMATCH` all answer "which host is this plugin running against?" — a
   question with one answer, known at compile time, in a single repo. **Do not add an `apiVersion`
   field.** The survey found zero systems using one even *with* external consumers (§8.1), and
   webpack's frozen `version: 2` shows what an unmaintained one is worth (§8.2).
4. **The union-of-two-shapes technique (§1.3) loses most of its value.** Its return is not having to
   migrate existing participants. You can migrate them. Take the clean single shape and pay Cost 1–3
   never.

**What it does NOT change — and this is where a "small N means anything goes" reading goes wrong:**

1. **The contract still has to be legible to a reader who was not there** — a future maintainer, or
   an agent. Every mechanism in §4.6 (schema-as-data), §2.3 (name the hooks you ignore), and sibling
   `b-optional-and-capabilities.md` (state the absent-property default at the contract) is about
   *legibility*, not compatibility. None of them is bought by external consumers and none is refunded
   by their absence.
2. **Silent-`undefined` is still the dominant failure mode**, and it is *worse* in-repo, not better,
   because there is no publish boundary and no peer-range gate to catch anything. Result 4 (§7.1)
   applies unchanged. **Required fields, or `@satisfies` at construction sites — this is the one
   place to spend effort.**
3. **The optional-with-documented-default posture is still right** wherever a genuine default exists
   — for clarity, not compatibility. "Optional" documents that the host has an answer; "required"
   documents that it does not. That distinction is information, and it survives having no external
   consumers.
4. **Direction of flow (§7.4) still governs.** Host→plugin objects are safe to widen; plugin→host
   values still need required fields or a loud failure. This is a property of information flow, not
   of publishing.
5. **Naming the participant in every diagnostic still matters.** With three adapters you will still
   read "adapter method returned undefined" at 2am and want to know which one.

**The one-line synthesis:** *no external consumers removes the need for COMPATIBILITY machinery and
removes none of the need for CLARITY machinery.* Every technique in this document is one or the
other; sort by that and the answer for our case falls out.

### 9.6 The concrete recommendation for this contract

INFERENCE, derived from the above:

1. **Do not version the contract.** No `apiVersion`, no capability-negotiation handshake. Zero of
   fifteen surveyed systems declare one, and the one that documents such a field never incremented it.
2. **When you need to widen: change the shape and fix all adapters in the same commit.** Skip the
   union, skip the runway. This is the option external projects wish they had.
3. **For a new required capability, in preference order:** (a) can the host default it? make it
   optional and **state the default at the contract**; (b) can it be a required *field in a value the
   adapter already returns*? do that, and throw on absence rather than defaulting (Node's
   `shortCircuit`); (c) only then a new required method.
4. **Shape hook signatures as Node does:** positional for identity arguments, **one extensible
   `context` object** for everything the host may later want to say, flowing **host → plugin**. That
   object can then grow forever without touching a signature (§2.6).
5. **Make every plugin→host object's fields REQUIRED**, or annotate its construction site with
   `/** @satisfies {T} */`. This is the single highest-value line of defense given Result 4, and it
   costs nothing.

   **Conditional, and the parent should confirm it:** every diagnostic in §7.1 — including
   `@satisfies` — requires the repo to actually run `tsc --checkJs` over these files in CI or a
   pre-commit gate. Plain ESM plus JSDoc types does **not** imply that. If `checkJs` is not wired
   up, every error in Result 1–7 is hypothetical, `@satisfies` is an inert comment, and the
   required-vs-optional distinction buys documentation only, not enforcement. I did not verify this
   repo's setup — that is the parent's call. If it turns out `checkJs` is *not* running, wiring it
   up is a higher-value change than anything else in this list, because it is the precondition for
   item 5 being real.
6. **Have the host destructure the full known adapter surface in one place**, Node's `pluckHooks`
   style — including names you have retired. It is the cheapest possible migration aid and it makes
   the contract's full shape readable at one site.
7. **Declare defaults and constraints as DATA on the adapter** where practical (ESLint's
   `meta.schema` / `meta.defaultOptions` model), because data declarations accumulate consumers —
   validation, docs, diagnostics — that code cannot (§4.6).

---

## 10. Everything flagged as unverified

- **Rollup**: only `isEntry`'s addition date (2.58.0, 2021-10-01, PR #4230) was verified for the
  `resolveId` options object; when `attributes`, `custom`, and `importerAttributes` were each added
  is **UNVERIFIED** (`importerAttributes` produced no hit in the v4 changelog). §1.5's "the object
  grew in a minor" rests on the one verified instance.
- **Strategy (ii)**, the spread-in default-implementation base object: **no research brief targeted
  it**, so its "not observed" status is absence of evidence, not evidence of absence. The
  recommendation against it in §9.1 rests on the snapshot-coupling argument, which is independent of
  the survey.
- **Node**: `module.md`'s YAML history for v16.12.0 states `globalPreload` was removed and
  `getGlobalPreload` added; the v16 changelog and the shipped v16.12.0 source both say the reverse
  (§2.1). I treat the changelog and source as authoritative and flag the API doc as wrong, but I did
  not open a Node issue or otherwise confirm upstream's intent.
- **PostCSS**: the Evil Martians plugin-migration article's *contents* were not fetched — verified
  only as the canonical link PostCSS points at from three places. No statement of regret about the
  8.0 redesign was found despite targeted searches (queries listed in §3.6);
  `@tailwindcss/postcss7-compat`'s npm `deprecated` field is `undefined` — it was abandoned, not
  formally deprecated.
- **ESLint**: whether a predecessor to `@eslint/compat` shipped under a different package name before
  2024-05-08. `@eslint/config-array` and `@eslint/plugin-kit` were not inspected for plugin-meta reads
  (the negative in §4.8 is verified for `eslint/lib` and `@eslint/config-helpers` only). The §4.3
  coverage-gap list is DERIVED (set-difference of two primary sources), not quoted. Interval
  arithmetic in §4.2 is derived from verified release dates.
- **Babel**: "first shipped in 7.0.0-beta.41" is INFERENCE from merge-commit `package.json` plus the
  next npm publish; **no changelog entry** for `assertVersion` or PR #7450 was found.
  `api.targets`/`api.assumption`/`api.async` were not found documented in a ten-file sample of
  `babel/website/docs/` — not all ~150 files were checked. Babel issue #7265 was not fetched.
- **Fastify**: `docs/Guides/Ecosystem.md` contains no version/support policy (a verified negative, but
  scoped to that file). `docs/Reference/Plugins.md`'s `fp(..., '0.x')` example is stale.
- **Cross-cutting B**: tsserver *wire-protocol* versioning was not investigated (only in-process LS
  plugins). VS Code's `enabledApiProposals` runtime gating is verified by docs and present in the
  gallery compat record, but the extension-host code path exposing per-proposal surfaces was not read.
  GitHub code-search counts are weak evidence for *absence* (default-branch indexing only) — the
  claims made are "the confirmed uses are gates and feature checks," never "almost nobody uses it."
  npm behavior was verified empirically on npm 11.16.0 only; npm 7–9 behavior is documented but not
  tested. Vite `api.version` is REFUTED as a documented API by grep at v5/v6/v7/main plus the `Plugin`
  interface; whether some community plugin puts a private `version` inside its own `api: {}` is
  UNVERIFIED.
- **Question A**: results are from TypeScript **7.0.2** under `--strict` with `--module nodenext`.
  Weak-type detection (Result 3) and `@satisfies` (Result 5) are long-standing TypeScript features but
  their *exact* introduction versions were not verified here; the behaviors were executed, not recalled.
