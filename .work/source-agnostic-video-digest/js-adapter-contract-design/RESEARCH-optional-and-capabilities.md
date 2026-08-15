---
topic: js-adapter-contract-design
section: optional-and-capabilities
abstract: "Four mature systems converge on documenting absent-method behaviour at the member itself ('if omitted, X'); the defect was never the caller's `if`, it was the undocumented `else`, and a method whose honest default is throw is a required method in disguise."
claims:
  - claim: "LSP, ESLint, MCP and Vite all document the omitted case AT the member — 'If omitted it defaults to utf-16', '(defaults to false if omitted)', 'clients MUST treat results that omit the field as complete'."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/"
        tier: 1
        pool: "Microsoft/LSP"
      - url: "https://eslint.org/docs/latest/extend/custom-rules"
        tier: 1
        pool: "ESLint"
      - url: "https://modelcontextprotocol.io/specification/2026-07-28/basic/index.md"
        tier: 1
        pool: "Anthropic/MCP"
  - claim: "Rollup deliberately conflates 'hook absent' with 'hook returned null' (NullValue = null | undefined | void), buying one host code path with no else branch and per-CALL rather than per-REGISTRATION opt-out."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://rollupjs.org/plugin-development/"
        tier: 1
        pool: "Rollup"
  - claim: "If a method's honest default is to THROW, it is not optional — it is a required method that was not required; Node models both arms in one prototype (_transform throws ERR_METHOD_NOT_IMPLEMENTED, _flush is absent and no-ops)."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://nodejs.org/api/stream.html"
        tier: 1
        pool: "Node.js"
      - url: "local probe: Node v24.18.0 prototype inspection"
        tier: 0
        pool: "first-party empirical (this machine)"
  - claim: "LSP-style declared capability flags are overkill here, and the discriminator is boundary-crossing rather than adapter count: every cross-process system surveyed declares, every in-process one sniffs or registers."
    confidence: MEDIUM
    tiers: [1]
    sources:
      - url: "https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/"
        tier: 1
        pool: "Microsoft/LSP"
      - url: "https://fastify.dev/docs/latest/Reference/Decorators/"
        tier: 1
        pool: "Fastify"
  - claim: "REFUTED premise: Rollup has no defaults-merging normalization step — PluginDriver filters with a bare `if (hook)` at dispatch, so {...defaults, ...adapter} has no bundler precedent and must be adopted on merits."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://rollupjs.org/plugin-development/"
        tier: 1
        pool: "Rollup"
produced_by: lane-b
---

# (b) Expressing OPTIONAL contract methods and their ABSENT-METHOD DEFAULT so the fallback is discoverable at the contract

Research pass for the source-adapter contract design. Every claim carries an inline URL and a
confidence marker.

## Confidence markers used

Matching the convention established by the sibling `e-design-rule.md` in this directory — two
orthogonal axes:

- **VERIFIED / UNVERIFIED / REFUTED** — whether the claim is supported by a source I reached. A
  fourth marker, **INFERENCE**, tags conclusions I drew *across* verified facts rather than read in
  any source; those are my reasoning and carry my fallibility, not a citation's authority.
- **`[EXACT]` / `[SUBSTANCE]`** — quote fidelity. `[EXACT]` = extracted byte-for-byte from primary
  text (raw HTML/Markdown/source fetched with `curl` and de-tagged locally, or executed locally).
  `[SUBSTANCE]` = the substance is verified but wording is not guaranteed verbatim.

All primary text in this document was fetched raw and de-tagged locally on 2026-08-14; nothing here
came through a summarizing extractor except where explicitly marked `[SUBSTANCE]`.

---

## 0. The question, sharpened

The call site today is:

```js
if (adapter.prepareLessonPage) { /* ... */ } else { /* implicit fallback nobody documented */ }
```

Two distinct defects are bundled here, and mature systems treat them separately:

1. **Where the fallback SEMANTICS live.** In the caller (bad) vs at the contract (good).
2. **Whether the host can KNOW an adapter's shape without invoking it.** Structural sniffing
   (`if (adapter.m)`) vs declared data (`adapter.supports.m === true`).

The survey below finds that (1) is solved by **documenting the absent-property default in the
contract's own type/doc comment** — an idiom LSP, ESLint, Node core, and Vite all use verbatim — and
that (2) is solved by declared capability flags, but is only *needed* when the participant is across
a boundary that makes sniffing impossible or too late. §8 lands both.

---

## 1. ROLLUP plugin hooks

Source: <https://rollupjs.org/plugin-development/> (fetched raw, de-tagged; Rollup docs site).
Type source: <https://raw.githubusercontent.com/rollup/rollup/master/src/rollup/types.d.ts>.
Dispatcher source: <https://raw.githubusercontent.com/rollup/rollup/master/src/utils/PluginDriver.ts>.

### 1.1 Optionality is stated structurally, once, at the top

VERIFIED `[EXACT]` — <https://rollupjs.org/plugin-development/>:

> "A Rollup plugin is an object with **one or more** of the properties, build hooks, and output
> generation hooks described below, and which follows our conventions."

That single sentence is the entire statement of hook optionality in the prose. There is **no
per-hook statement of what happens when the hook is absent** for any of `resolveId`, `load`,
`transform`, `buildStart`, `renderChunk`. VERIFIED by exhaustive read of those five hook sections.

### 1.2 What IS documented per-hook: the `null` return

VERIFIED `[EXACT]` — `load`, <https://rollupjs.org/plugin-development/#load>:

> "Defines a custom loader. […] **Returning `null` defers to other load functions (and eventually
> the default behavior of loading from the file system).**"

VERIFIED `[EXACT]` — `renderChunk`, <https://rollupjs.org/plugin-development/#renderchunk>:

> "Can be used to transform individual chunks. Called for each Rollup output chunk file. **Returning
> `null` will apply no transformations.**"

VERIFIED `[EXACT]` — the canonical worked example at the top of the page, which teaches the
convention twice in eight lines,
<https://rollupjs.org/plugin-development/#a-simple-example>:

```js
resolveId(source) {
  if (source === 'virtual-module') {
    // this signals that Rollup should not ask other plugins or check
    // the file system to find this id
    return source;
  }
  return null; // other ids should be handled as usually
},
load(id) {
  if (id === 'virtual-module') {
    return 'export default "This is virtual!"';
  }
  return null; // other ids should be handled as usually
}
```

`resolveId` itself carries **no** "returning null defers…" sentence in its own prose; the type
`ResolveIdResult = string | null | false | PartialResolvedId` and the example carry it. VERIFIED —
`resolveId` section read in full.

`transform` carries no whole-hook null statement either — only *per-field* ones, e.g. VERIFIED
`[EXACT]`: "If `null` is returned or the flag is omitted, then `moduleSideEffects` will be
determined by the `load` hook that loaded this module, the first `resolveId` hook that resolved this
module, the `treeshake.moduleSideEffects` option, or eventually default to `true`."

Note the phrase **"or the flag is omitted"** — Rollup explicitly equates *returning null for a
field* with *omitting the field*, in prose, at the contract. That is the small-scale version of the
exact pattern this design pass is looking for.

`buildStart` documents no return semantics at all (it is `parallel`, return ignored). VERIFIED
`[EXACT]`: "Called on each rollup.rollup build. This is the recommended hook to use when you need
access to the options passed to `rollup.rollup()`…".

### 1.3 The hook-kind classification IS the absent-hook documentation

VERIFIED `[EXACT]` — <https://rollupjs.org/plugin-development/#build-hooks>:

> "There are different kinds of hooks:
>
> - **`async`**: The hook may also return a Promise resolving to the same type of value; otherwise,
>   the hook is marked as `sync`.
> - **`first`**: If several plugins implement this hook, the hooks are run sequentially until a hook
>   returns a value other than `null` or `undefined`.
> - **`sequential`**: If several plugins implement this hook, all of them will be run in the
>   specified plugin order. If a hook is async, subsequent hooks of this kind will wait until the
>   current hook is resolved.
> - **`parallel`**: If several plugins implement this hook, all of them will be run in the specified
>   plugin order. If a hook is async, subsequent hooks of this kind will be run in parallel and not
>   wait for the current hook."

Every hook's doc block then carries a `Kind:` row — e.g. `resolveId` → `async, first`; `load` →
`async, first`; `transform` → `async, sequential`; `buildStart` → `async, parallel`; `renderChunk` →
`async, sequential`. VERIFIED `[EXACT]` (all five read directly; full census of 27 hooks extracted).

**This classification is the absent-hook contract, expressed once for a whole class of hooks instead
of 27 times.** Read the definitions with "if several plugins implement this hook" as the operative
clause: each one is phrased over *the set of plugins that implement it*, so a plugin that does not
implement it is simply not in the set. Absent-hook behavior is therefore derivable from two facts —
the kind, and the phrasing — rather than restated per hook. That is a genuinely good design and a
directly transferable idea: **classify your optional methods, document the class once.**

The classification is not merely prose. It is machine-readable in the published types. VERIFIED
`[EXACT]` — `src/rollup/types.d.ts`:

```ts
export type FirstPluginHooks =
	| 'load'
	| 'renderDynamicImport'
	| 'resolveDynamicImport'
	| 'resolveFileUrl'
	| 'resolveId'
	| 'resolveImportMeta'
	| 'shouldTransformCachedModule';

export type SequentialPluginHooks =
	| 'augmentChunkHash'
	| 'generateBundle'
	| 'onLog'
	| 'options'
	| 'outputOptions'
	| 'renderChunk'
	| 'transform';

export type ParallelPluginHooks = Exclude<
	keyof FunctionPluginHooks | AddonHooks,
	FirstPluginHooks | SequentialPluginHooks
>;
```

### 1.4 Is every hook optional in the TypeScript `Plugin` interface? Yes — via `Partial`, not `?`

VERIFIED `[EXACT]` — `src/rollup/types.d.ts`:

```ts
export interface Plugin<A = any> extends OutputPlugin, Partial<PluginHooks> {
	// for inter-plugin communication
	api?: A | undefined;
}
```

`FunctionPluginHooks` declares every hook as **required** (`buildStart: (…) => void;`,
`load: LoadHook;`, `transform: TransformHook;` — no `?` anywhere). Optionality is applied wholesale
by the `Partial<PluginHooks>` mapped type. VERIFIED `[EXACT]` — full interface read.

**Consequence, and it is the crux of this research question:** because optionality is applied by a
mapped type rather than written per-property, there is **nowhere on the interface to hang a per-hook
"if omitted, X happens" doc comment.** The `Partial<>` trick buys terseness and costs exactly the
discoverability affordance we are shopping for. Contrast LSP §3.4, which writes `?` per property and
*therefore has a place to put the default*.

### 1.5 KEY QUESTION → Does Rollup conflate "hook absent" with "hook returned null"?

**Yes, deliberately, and the conflation is encoded in both the runtime and the type system.**
VERIFIED.

Runtime — `PluginDriver.ts`. Dispatch filters to plugins that *have* the hook, using a bare
truthiness test. VERIFIED `[EXACT]`:

```ts
function getSortedValidatedPlugins(hookName, plugins, validateHandler = validateFunctionPluginHandler) {
	const pre = []; const normal = []; const post = [];
	for (const plugin of plugins) {
		const hook = plugin[hookName];
		if (hook) { /* … classify by order, push … */ }
	}
```

and the comment above `runHook`, VERIFIED `[EXACT]`:

```ts
// We always filter for plugins that support the hook before running it
```

Then the `first` driver treats a null *return* identically. VERIFIED `[EXACT]`:

```ts
// chains, first non-null result stops and returns result and last plugin
async hookFirstAndGetPlugin(hookName, parameters, replaceContext, skipped) {
	for (const plugin of this.getSortedPlugins(hookName)) {
		if (skipped?.has(plugin)) continue;
		const result = await this.runHook(hookName, parameters, plugin, replaceContext);
		if (result != null) return [result, plugin];
	}
	return null;
}
```

A plugin without the hook is skipped by the filter; a plugin whose hook returns null fails
`result != null` and is skipped by the loop. **Observationally identical.**

Type system — the conflation is named. VERIFIED `[EXACT]` — `src/rollup/types.d.ts`:

```ts
type NullValue = null | undefined | void;
```

`void` is in the union. A hook that falls off the end without returning is the same as a hook that
returns `null` is the same as no hook at all.

**What the conflation buys** (this is the design payoff to steal):

- **One host code path, not two.** There is no `else` branch anywhere in `PluginDriver` for
  "plugin lacks this hook" — the filter and the null-check collapse into one loop.
- **Opt-out becomes per-call rather than per-registration.** A plugin can decline on Tuesday and
  handle on Wednesday, or decline for `.css` and handle `.ts`, without changing its declared shape.
  A capability *flag* cannot express that; a null return can. This is why bundler hooks are
  chain-of-responsibility and not capability-declared.
- **Adding a hook is non-breaking in both directions.** Existing plugins omit it (filtered out) and
  new plugins can return null from it (loop continues).

**What it costs:** the host cannot answer "does this plugin do resolution?" without running a build.
Rollup does not need to answer that, so it does not pay for the answer. Whether *your* host needs
to answer it is the deciding question in §8.

### 1.6 REFUTATION — Rollup has no defaults-merging normalization step

The task brief suggests checking "Rollup's normalization step" as a base-default-object precedent.
**REFUTED.** VERIFIED `[EXACT]` from `PluginDriver.ts`: Rollup normalizes hook *shape* (a hook may
be a function or `{ handler, order, filter }` — `const handler = typeof hook === 'object' ? hook.handler : hook;`)
but never fills in absent hooks. Presence is resolved at dispatch by `if (hook)`, per hook, per call,
cached per hook name in `this.sortedPlugins`. There is no `{...defaults, ...plugin}` anywhere in the
driver.

---

## 2. VITE plugin API

Source: <https://vite.dev/guide/api-plugin.md> and
<https://vite.dev/guide/api-environment-plugins.md> (vite.dev serves an LLM-oriented Markdown twin
of every docs page — used here so all quotes are byte-exact rather than de-tagged). Docs version
shown on the rendered page: **v8.2.1**. VERIFIED `[EXACT]` from <https://vite.dev/guide/api-plugin>.

### 2.1 PREMISE CORRECTION — Vite 8 is a Rolldown superset, not a Rollup superset

The brief says "Rollup-superset hooks." **PARTIALLY REFUTED for the current version.** VERIFIED
`[EXACT]` — <https://vite.dev/guide/api-plugin.md>:

> "Vite plugins extends **Rolldown's** plugin interface with a few extra Vite-specific options. As a
> result, you can write a Vite plugin once and have it work for both dev and build."
>
> "It is recommended to go through **Rolldown's plugin documentation** first before reading the
> sections below."

and VERIFIED `[EXACT]`:

> "During dev, the Vite dev server creates a plugin container that invokes
> [Rolldown Build Hooks](https://rolldown.rs/apis/plugin-api#build-hooks) the same way Rolldown does
> it."

The build-hook links now point at `rolldown.rs`, not `rollupjs.org`. The premise is *substantively*
still fine — Rolldown is deliberately Rollup-plugin-compatible and the doc has a
"Rolldown Plugin Compatibility" section — but "Rollup-superset" is stale as a statement about Vite 8.
Nothing in this analysis turns on it.

### 2.2 Vite-specific hooks document `void` returns, not absence — same gap as Rollup

VERIFIED `[EXACT]` — signatures as published:

| Hook | Type | Kind |
| --- | --- | --- |
| `config` | `(config: UserConfig, env: {…}) => UserConfig \| null \| void` | `async`, `sequential` |
| `configResolved` | `(config: ResolvedConfig) => void \| Promise<void>` | `async`, `parallel` |
| `transformIndexHtml` | `IndexHtmlTransformHook \| { order?, handler }` | `async`, `sequential` |
| `handleHotUpdate` | `(ctx: HmrContext) => Array<ModuleNode> \| void \| Promise<…>` | `async`, `sequential` |
| `hotUpdate` | `(this: { environment }, options: HotUpdateOptions) => Array<EnvironmentModuleNode> \| void \| Promise<…>` | `async`, `sequential` |

(`hotUpdate` is the Environment-API successor, documented separately at
<https://vite.dev/guide/api-environment-plugins.md#the-hotupdate-hook>; `handleHotUpdate` is still
documented in `api-plugin.md` at v8.2.1. Both present. VERIFIED.)

None of these five states what happens if the hook is omitted. The `void` in each return type is the
same conflation Rollup encodes — decline by returning nothing is spelled the same as never
implementing it.

`transformIndexHtml` does document one absent-*property* default, for a sub-property rather than the
hook: VERIFIED `[EXACT]` — "By default `order` is `undefined`, with this hook applied after the HTML
has been transformed."

### 2.3 THE FINDING — `applyToEnvironment` documents its own absent-hook default, in the contract

This is the single closest precedent in this whole survey to what the design pass wants. VERIFIED
`[EXACT]` — <https://vite.dev/guide/api-environment-plugins.md#per-environment-plugins-using-the-applytoenvironment-hook>:

```js
applyToEnvironment(environment) {
  // return true if this plugin should be active in this environment,
  // or return a new plugin to replace it.
  // if the hook is not used, the plugin is active in all environments
},
```

> "**if the hook is not used, the plugin is active in all environments**"

The absent-method default is written **inside the contract's own canonical example, next to the
method it governs**, in a JS comment — not in the host, not in a caller, not in a changelog. That is
exactly the affordance this design pass is chasing, and it is achieved with one comment line and
zero machinery. Note also the sentence that follows the sample, VERIFIED `[EXACT]`: "If a plugin
isn't environment aware and has state that isn't keyed on the current environment, the
`applyToEnvironment` hook allows to easily make it per-environment."

### 2.4 `apply` and `enforce` — declarative properties, with a caveat that must be stated

`enforce` is a pure data property. VERIFIED `[EXACT]` —
<https://vite.dev/guide/api-plugin.md#plugin-ordering>:

> "A Vite plugin can additionally specify an `enforce` property (similar to webpack loaders) to
> adjust its application order. The value of `enforce` can be either `"pre"` or `"post"`. The
> resolved plugins will be in the following order:
>
> - Alias
> - User plugins with `enforce: 'pre'`
> - Vite core plugins
> - User plugins without enforce value
> - Vite build plugins
> - User plugins with `enforce: 'post'`
> - Vite post build plugins (minify, manifest, reporting)"

The absent-value default is documented **by position in the list** — "User plugins without enforce
value" is a literal row in the ordering table. That is a second, different, and quite elegant way to
put an omitted-property default at the contract: make the omitted case a named entry in the
enumeration of outcomes.

`apply` — **the brief's premise needs qualifying.** VERIFIED `[EXACT]` —
<https://vite.dev/guide/api-plugin.md#conditional-application>:

> "**By default plugins are invoked for both serve and build.** In cases where a plugin needs to be
> conditionally applied only during serve or build, use the `apply` property to only invoke them
> during `'build'` or `'serve'`"
>
> ```js
> function myPlugin() {
>   return { name: 'build-only', apply: 'build' } // or 'serve'
> }
> ```
>
> "**A function can also be used for more precise control:**"
>
> ```js
> apply(config, { command }) {
>   // apply only on build but not for SSR
>   return command === 'build' && !config.build.ssr
> }
> ```

So `apply` is `'build' | 'serve' | ((config, env) => boolean)`. **The brief's claim that `apply` is a
declarative property and not a method is only true of its scalar form.** UNVERIFIED as stated;
qualified as above.

This qualification *strengthens* rather than weakens the discoverability argument, and here is the
precise reason: even in its function form, `apply` is (a) a **fixed, named key** an author finds by
reading the contract, (b) evaluated **once, at plugin-resolution time**, with the whole config in
hand, and (c) answers **one closed question** with a boolean. It is a *predicate about the plugin*,
not a unit of the plugin's work. Compare `resolveId`, which must be called an unbounded number of
times with unbounded arguments before the host learns anything general. So the useful distinction is
not "property vs function"; it is:

> **A capability declaration is answerable at a known time, from state the host already has, once.
> A hook is not.**

That is the property to preserve when designing a small contract — and it is why a *function-valued*
declaration is still a declaration, while a nullable hook is not.

Also VERIFIED `[EXACT]`, a second declarative data flag on the same plugin object —
<https://vite.dev/guide/api-environment-plugins.md#shared-plugins-during-build>:

> "…so plugin authors can opt-in for a particular plugin to be shared by setting the
> `sharedDuringBuild` flag to `true`."

```js
return {
  name: 'shared-plugin',
  transform(code, id) { ... },
  // Opt-in into a single instance for all environments
  sharedDuringBuild: true,
}
```

`sharedDuringBuild` is a boolean capability/behavior flag on a plugin object in a mainstream JS
plugin system — relevant precedent for §7, where the question is whether declared data has any
foothold in JS at all.

### 2.5 `configDefaults` — could not verify

The brief suggests `configDefaults` as a Vite base-defaults precedent. **UNVERIFIED.** I searched
<https://vite.dev/guide/api-plugin.md>, <https://vite.dev/guide/api-environment-plugins.md>,
<https://vite.dev/guide/api-javascript.md>, <https://vite.dev/config/shared-options.md>, and
<https://raw.githubusercontent.com/vitejs/vite/main/packages/vite/src/node/index.ts> (the public
export barrel) — the identifier `configDefaults` appears in none of them. It may have existed in an
earlier version or under a different surface; I did not reach a source confirming it, so nothing in
this document rests on it.

### 2.6 KEY QUESTION → Does Vite conflate absent with null?

**Yes for its hooks (same as Rollup — `void` in every return union), no for its declarative
properties.** `enforce`, `apply`, and `sharedDuringBuild` each have a **documented value for the
omitted case** ("User plugins without enforce value" in the order list; "By default plugins are
invoked for both serve and build"; opt-in implies default false), and the host reads all three
*before* any hook runs. VERIFIED.

---

## 3. LANGUAGE SERVER PROTOCOL — capability negotiation

Source: the specification itself,
<https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>
(fetched raw, de-tagged locally; all quotes `[EXACT]`).

### 3.1 The canonical statement of why capabilities exist

VERIFIED `[EXACT]`:

> "**Capabilities**
>
> Not every language server can support all features defined by the protocol. LSP therefore provides
> 'capabilities'. A capability groups a set of language features. A development tool and the language
> server announce their supported features using capabilities. As an example, a server announces
> that it can handle the `textDocument/hover` request, but it might not handle the
> `workspace/symbol` request. Similarly, a development tool announces its ability to provide about
> to save notifications before a document is saved, so that a server can compute textual edits to
> format the edited document before it is saved.
>
> **The set of capabilities is exchanged between the client and server during the `initialize`
> request.**"

### 3.2 How a server declares support

VERIFIED `[EXACT]`:

> "The `initialize` request is sent as the first request from the client to the server. If the server
> receives a request or notification before the `initialize` request it should act as follows:
> For a request the response should be an error with code: `-32002`. […]
> **Until the server has responded to the `initialize` request with an `InitializeResult`, the client
> must not send any additional requests or notifications to the server.** […]
> The `initialize` request may only be sent once."

The server's declaration is the `capabilities` field of `InitializeResult`, typed
`ServerCapabilities`. Every LSP message's spec page then carries its own **Client capability** and
**Server Capability** blocks naming the exact property path. VERIFIED `[EXACT]`, from the spec's own
description of its documentation format:

> "an optional **Client capability** section describing the client capability of the request. This
> includes the client capabilities property path and JSON structure."
>
> "an optional **Server Capability** section describing the server capability of the request. This
> includes the server capabilities property path and JSON structure. **Clients should ignore server
> capabilities they don't understand** (e.g. the `initialize` request shouldn't fail in this case)."

Worked instance — `textDocument/hover`. VERIFIED `[EXACT]`:

> "**Server Capability:**
> property name (optional): `hoverProvider`
> property type: `boolean | HoverOptions` where `HoverOptions` is defined as follows:
> `export interface HoverOptions extends WorkDoneProgressOptions { }`"

**Transferable structural idea:** the capability declaration is documented *on the page for the
method it governs*, not in a separate capabilities appendix. Locality is what makes it discoverable.

### 3.3 KEY SPEC TEXT — what absence means, stated once, normatively

This is the passage that resolves the "capability absent vs present-but-empty" ambiguity, and it is
the most directly reusable sentence in the entire survey. VERIFIED `[EXACT]`:

> "…the `ClientCapabilities` object literal can have more properties set than currently defined.
> Servers receiving a `ClientCapabilities` object literal with unknown properties should ignore
> these properties. **A missing property should be interpreted as an absence of the capability. If a
> missing property normally defines sub properties, all missing sub properties should be interpreted
> as an absence of the corresponding capability.**"

So LSP's answer to the ambiguity is a **global default rule plus per-property overrides**:

- Global rule: missing ⇒ absent, recursively into sub-objects.
- Per-property override wherever the truth is something other than "absent" — written as a doc
  comment on the property itself (§3.4).

And a third case, worth naming because a small contract will hit it: capabilities that **cannot** be
omitted, because they predate the capability mechanism. VERIFIED `[EXACT]`:

> "Client capabilities got introduced with version 3.0 of the protocol. They therefore only describe
> capabilities that got introduced in 3.x or later. Capabilities that existed in the 2.x version of
> the protocol are still mandatory for clients. **Clients cannot opt out of providing them.** So even
> if a client omits the `ClientCapabilities.textDocument.synchronization` it is still required that
> the client provides text document synchronization (e.g. open, changed and close notifications)."

That is the required-vs-optional split written into the negotiation layer itself: the *declaration*
is optional, the *behavior* is mandatory.

### 3.4 The `?` + `boolean | Options` union shape, and what each variant expresses

VERIFIED `[EXACT]` — `ServerCapabilities`, verbatim excerpt:

```ts
interface ServerCapabilities {

	/**
	 * The position encoding the server picked from the encodings offered
	 * by the client via the client capability `general.positionEncodings`.
	 *
	 * If the client didn't provide any position encodings the only valid
	 * value that a server can return is 'utf-16'.
	 *
	 * If omitted it defaults to 'utf-16'.
	 *
	 * @since 3.17.0
	 */
	positionEncoding?: PositionEncodingKind;

	/**
	 * Defines how text documents are synced. Is either a detailed structure
	 * defining each notification or for backwards compatibility the
	 * TextDocumentSyncKind number. If omitted it defaults to
	 * `TextDocumentSyncKind.None`.
	 */
	textDocumentSync?: TextDocumentSyncOptions | TextDocumentSyncKind;

	/**
	 * The server provides completion support.
	 */
	completionProvider?: CompletionOptions;

	/**
	 * The server provides hover support.
	 */
	hoverProvider?: boolean | HoverOptions;

	/**
	 * The server provides go to declaration support.
	 *
	 * @since 3.14.0
	 */
	declarationProvider?: boolean | DeclarationOptions
		| DeclarationRegistrationOptions;

	/**
	 * The server provides code actions. The `CodeActionOptions` return type is
	 * only valid if the client signals code action literal support via the
	 * property `textDocument.codeAction.codeActionLiteralSupport`.
	 */
	codeActionProvider?: boolean | CodeActionOptions;
```

Read the shapes against each other — LSP is using **four** distinct declarations here, and each one
says a different thing:

| Shape | Example | Expresses |
| --- | --- | --- |
| `?: boolean \| Options` | `hoverProvider` | tri-state: **absent** = unsupported; **`true`** = supported, all defaults; **`Options`** = supported, configured |
| `?: Options` (no boolean) | `completionProvider` | the feature is **meaningless without configuration**, so there is no bare "yes" — declaring support and configuring it are the same act |
| `?: T` + "If omitted it defaults to X" | `positionEncoding`, `textDocumentSync` | **the omitted case is NOT "absent"** — it is a specific documented value, so the global rule of §3.3 is overridden right here |
| `?: boolean` | `dynamicRegistration`, `applyEdit` | plain yes/no, absent = no |

The `boolean | Options` union is a real design lesson, distinct from "make it optional": it lets a
participant say *yes* without being forced to author a configuration object, while leaving room to
configure later — **without a breaking change to the declaration's type**. `true` today,
`{ … }` tomorrow, same property.

The middle row is the one to steal for a JS adapter contract: **a `?` with a doc comment saying what
the omitted value means is a complete, self-contained statement of the absent-method default, and it
lives on the property.** That is the whole answer to the brief's question, in one line, from the
canonical authority on capability design.

### 3.5 `dynamicRegistration`

VERIFIED `[EXACT]` — the doc comment form, e.g. under `workspace.fileOperations`:

```ts
/**
 * Whether the client supports dynamic registration for file
 * requests/notifications.
 */
dynamicRegistration?: boolean;
```

and under `HoverClientCapabilities`:

```ts
export interface HoverClientCapabilities {
	/**
	 * Whether hover supports dynamic registration.
	 */
	dynamicRegistration?: boolean;
	…
}
```

VERIFIED `[EXACT]` — `client/registerCapability`:

> "The `client/registerCapability` request is sent from the server to the client to register for a
> new capability on the client side. **Not all clients need to support dynamic capability
> registration. A client opts in via the `dynamicRegistration` property on the specific client
> capabilities. A client can even provide dynamic registration for capability A but not for
> capability B** (see `TextDocumentClientCapabilities` as an example).
>
> **Server must not register the same capability both statically through the `initialize` result and
> dynamically for the same document selector.** If a server wants to support both static and dynamic
> registration it needs to check the client capability in the `initialize` request and only register
> the capability statically if the client doesn't support dynamic registration for that capability."

Two design lessons here, both directly relevant:

1. **`dynamicRegistration` is a capability ABOUT capabilities** — a meta-capability, declared with
   the same `?: boolean` shape. Capability declaration is uniform enough to describe itself.
2. **The static/dynamic exclusivity rule** shows the cost of adding a second declaration channel:
   the spec has to write an explicit anti-double-declaration rule, and put the burden of resolving it
   on the server. A small contract that adds capability flags *alongside* method presence inherits
   exactly this class of rule ("what if the flag and the method disagree?"). §7 returns to it.

### 3.6 KEY QUESTION → Why declare, when you could call and see?

Because in LSP **"call and see" is not available, and would be wrong even if it were.** Four reasons,
each grounded above:

1. **There is nothing to sniff.** The participants are separate processes exchanging JSON-RPC over a
   pipe. A client cannot introspect a server for a `hover` method; there is no object. Declaration is
   not a *stylistic preference over* duck typing — it is the **only** mechanism available. This is
   the load-bearing fact, and it is the one that does *not* transfer to an in-process JS adapter.
2. **The host must decide before calling.** LSP clients light up UI affordances, register keybindings,
   and route user gestures. "Is Go to Definition enabled in this menu?" must be answered without
   performing a Go to Definition. VERIFIED by the `initialize` ordering rule (§3.2): the client is
   *forbidden* from sending anything until it holds the declaration.
3. **Probing has cost and side effects.** A call to find out whether calls are supported is a
   round-trip per feature per server, and for mutating methods it is not even safe.
4. **A declaration is a stable artifact.** It can be logged, cached, diffed across versions,
   displayed, and tested against — none of which a per-call null return supports.

**The honest counter-statement, which matters for §8:** none of reasons 1–4 are about *contract
discoverability for the implementer*. LSP gets discoverability from something orthogonal and much
cheaper — writing `?` per property with a doc comment stating the omitted meaning (§3.3, §3.4). The
capability *flags* buy the host runtime reasoning; the *doc comments on optional properties* buy the
author comprehension. **These are separable, and only the second one is what the brief is asking
for.** A small JS contract can take the second without the first.

### 3.7 Is there spec text on "capability absent" vs "capability present but empty/default"?

**Yes** — §3.3's "A missing property should be interpreted as an absence of the capability. If a
missing property normally defines sub properties, all missing sub properties should be interpreted as
an absence of the corresponding capability." VERIFIED `[EXACT]`.

Note precisely what that rule does and does not do. It collapses *missing* into *absent* by default,
and it recurses. It does **not** say that a present-but-empty object means absent — `hoverProvider:
{}` (an empty `HoverOptions`) means **supported with defaults**, and `hoverProvider: false` means
**not supported**, and `hoverProvider` missing means **not supported**. So LSP has one genuine
three-into-two collapse (missing ≡ `false`) and one genuine distinction preserved (`{}` ≠ missing).
That is the tri-state the `boolean | Options` union exists to express (§3.4).

---

## 4. MODEL CONTEXT PROTOCOL — a 2026 redesign, and a REFUTED premise

Source: <https://modelcontextprotocol.io/specification/> — current version **2026-07-28**, VERIFIED
`[EXACT]` from the page's own version selector. Spec pages fetched as Markdown via the paths listed
in <https://modelcontextprotocol.io/llms.txt>.

### 4.1 REFUTATION — MCP no longer declares capabilities during `initialize`; there is no `initialize`

The brief asks "How does it declare capabilities during `initialize`". **REFUTED for the current
spec.** VERIFIED `[EXACT]` —
<https://modelcontextprotocol.io/specification/2026-07-28/changelog.md>, Major changes, item 2:

> "**Make MCP stateless: remove the `initialize`/`notifications/initialized` handshake.** Every
> request now carries its protocol version and client capabilities in `_meta`
> (`io.modelcontextprotocol/protocolVersion`, `io.modelcontextprotocol/clientCapabilities`). Clients
> SHOULD identify themselves on each request (`io.modelcontextprotocol/clientInfo`), and servers
> SHOULD identify themselves in each result's `_meta` (`io.modelcontextprotocol/serverInfo`). Version
> mismatches return `UnsupportedProtocolVersionError` (SEP-2575)."

and item 3:

> "**Add `server/discover`: servers MUST implement this RPC to advertise their supported protocol
> versions, capabilities, and identity.** Clients MAY call it before any other request for up-front
> version selection, or use it as a backward-compatibility probe on STDIO (SEP-2575)."

VERIFIED `[EXACT]` — <https://modelcontextprotocol.io/specification/2026-07-28/basic/index.md>:

> "**Statelessness**
>
> The Model Context Protocol (MCP) is a **stateless protocol**: all the information needed to process
> a request is contained in the request itself. A server processes each request independently; no
> state should be inferred from previous requests, even those on the same connection or stream.
>
> Specifically:
>
> - Servers **MUST NOT** rely on prior requests over the same connection to establish context (e.g.,
>   capabilities, protocol version, client identity). Every request supplies this metadata in its
>   `_meta` field."

Per-request client declaration, VERIFIED `[EXACT]` (from the reserved-`_meta`-keys table):

| Key | Type | Required | Description |
| --- | --- | --- | --- |
| `io.modelcontextprotocol/protocolVersion` | `string` | Yes | Protocol version for this request |
| `io.modelcontextprotocol/clientInfo` | `Implementation` | No | Client name and version |
| `io.modelcontextprotocol/clientCapabilities` | `ClientCapabilities` | **Yes** | Client capabilities relevant to this request |

The brief's premise held for **2025-06-18** and earlier. VERIFIED `[EXACT]` —
<https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle.md>: "Client and server
capabilities establish which optional protocol features will be available during **the session**."

### 4.2 THE MEANINGFUL DIFFERENCE FROM LSP — absence is a hard, typed error

This is the design fork the brief asks about in exhibit 5, answered by a live protocol. VERIFIED
`[EXACT]` — <https://modelcontextprotocol.io/specification/2026-07-28/basic/index.md>:

> "**A server MUST NOT rely on capabilities the client has not declared.** If processing a request
> requires a capability the client did not include in `io.modelcontextprotocol/clientCapabilities`,
> the server **MUST** return a `MissingRequiredClientCapabilityError` (`-32021`) whose
> `data.requiredCapabilities` lists the missing capabilities. On HTTP, the response status **MUST**
> be `400 Bad Request`."

Contrast LSP, where an undeclared capability means the counterpart simply must not ask. MCP:

- names a **dedicated error type and code** for the undeclared-capability case (`-32021`), and
- makes the error **self-describing** — `data.requiredCapabilities` tells the caller exactly which
  declarations would have made the call succeed.

**That second point is the transferable one and it is easy to underrate.** An error that names the
missing capability turns a runtime failure into documentation delivered at the moment of need. It is
the throw-fork done well: not "unsupported", but "unsupported: you needed X".

The 2025 formulation of the same discipline, VERIFIED `[EXACT]` —
<https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle.md>: "Both parties **MUST**:
Respect the negotiated protocol version; **Only use capabilities that were successfully
negotiated**."

### 4.3 Capability shape and sub-capabilities

VERIFIED `[EXACT]` — `server/discover` response,
<https://modelcontextprotocol.io/specification/2026-07-28/server/discover.md>:

```json
"result": {
  "resultType": "complete",
  "supportedVersions": ["2026-07-28"],
  "capabilities": { "tools": {}, "resources": {} },
  …
}
```

Presence of the key = supported; the object's contents are the sub-capabilities; `{}` = supported
with no sub-capabilities. Same resolution as LSP's `hoverProvider: {}` — **empty object means
present-with-defaults, not absent.** And `server/discover` is itself **not** optional: "Servers
**MUST** implement it." VERIFIED `[EXACT]`.

Sub-capabilities, VERIFIED `[EXACT]` —
<https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle.md>:

> "Capability objects can describe sub-capabilities like:
>
> - `listChanged`: Support for list change notifications (for prompts, resources, and tools)
> - `subscribe`: Support for subscribing to individual items' changes (resources only)"

In 2026-07-28 these were reworked into explicit opt-in subscription types. VERIFIED `[EXACT]`,
changelog item 4: "Clients opt in to specific types (`toolsListChanged`, `promptsListChanged`,
`resourcesListChanged`, `resourceSubscriptions`); the server acknowledges and tags notifications with
`io.modelcontextprotocol/subscriptionId`."

### 4.4 A bonus omitted-field default, stated normatively

VERIFIED `[EXACT]` — changelog item 8:

> "All results now carry a required `resultType` field: `"complete"` for ordinary results and
> `"input_required"` for multi round-trip request interim results. **Clients MUST treat results from
> earlier-protocol servers that omit the field as `"complete"`.**"

A one-sentence normative absent-field default, written at the contract. Same idiom as LSP's "If
omitted it defaults to 'utf-16'." Two independent modern protocols converge on it.

### 4.5 KEY QUESTION → Does MCP differ meaningfully from LSP?

**Yes, in three ways.** VERIFIED.

1. **Declaration cadence:** LSP = once per session at `initialize`; MCP 2026-07-28 = **per request**,
   in `_meta`. MCP paid for horizontal scalability and connection-independence by re-sending the
   declaration on every call.
2. **Absence handling:** LSP = the counterpart must not ask (silent, prohibitive); MCP = the
   counterpart **must** be told, with a typed, self-describing error.
3. **Discovery is a method, not a handshake:** `server/discover` is an ordinary RPC that servers MUST
   implement and clients MAY call. Capability discovery became a *required capability*, which is a
   neat way to escape the bootstrap problem.

MCP's own lineage note, VERIFIED `[EXACT]` — <https://modelcontextprotocol.io/specification/>: "MCP
takes some inspiration from the Language Server Protocol…". So the divergences above are informed
revisions, not independent invention.

---

## 5. BASE DEFAULT-IMPLEMENTATION OBJECT — `{...defaults, ...adapter}`

### 5.1 Precedent search result: the literal object-spread form is NOT the JS mainstream

**REFUTED as a widespread bundler/test-runner idiom**, on the evidence I reached:

- **Rollup** — REFUTED, §1.6. Filters by `if (hook)` at dispatch; no defaults merge.
- **Vite** — no defaults merge found in the plugin docs; `applyToEnvironment` (§2.3) documents its
  absent-hook default in prose and the container presence-checks.
- **esbuild** — a *third* structural answer, not defaults-merging: there are no optional methods at
  all. VERIFIED `[EXACT]` — <https://esbuild.github.io/plugins/>: "An esbuild plugin is an object
  with a `name` and a `setup` function." Capability is expressed by **what the plugin registers**
  inside `setup(build)` via `build.onResolve({ filter }, cb)` / `build.onLoad({ filter }, cb)`.
  VERIFIED `[EXACT]`: "The `onResolve` API is meant to be called within the `setup` function and
  **registers a callback to be triggered in certain situations**." Registration-based capability is
  the closest thing in the JS bundler world to a declared capability: the host holds an explicit list
  of what this plugin handles, and the `filter` regex narrows it, all without invoking plugin logic.
  Worth noting as an option, though it costs a level of indirection that a 2–3 adapter contract does
  not need.

So: if you adopt `{...defaults, ...adapter}`, do it because it is right for your contract, **not**
because bundlers do it. They mostly do not. That is an honest finding and it removes a false
appeal-to-precedent from the decision.

### 5.2 Real precedent for base defaults: Node.js core streams — and it uses BOTH forks at once

Node core is the strongest available precedent, and it is unusually instructive because it makes the
throw-vs-benign choice *visible in the prototype* and applies each where it belongs.

Documented requirement levels, VERIFIED `[EXACT]` — <https://nodejs.org/api/stream.html>:

- `readable._read(size)`: "**All `Readable` stream implementations must provide an implementation of
  the `readable._read()` method** to fetch data from the underlying resource."
- `transform._transform(chunk, encoding, callback)`: "**All `Transform` stream implementations must
  provide a `_transform()` method** to accept input and produce output."
- `transform._flush(callback)`: "…**Custom `Transform` implementations may implement** the
  `transform._flush()` method. This will be called when there is no more written data to be consumed,
  but before the `'end'` event is emitted…"
- `writable._construct(callback)`: "It **may** be implemented by child classes… **This optional
  function** will be called in a tick after the stream constructor has returned…"

Implementation, VERIFIED `[EXACT]` from
<https://raw.githubusercontent.com/nodejs/node/v24.x/lib/internal/streams/transform.js>:

```js
// line 127
  if (typeof this._flush === 'function' && !this.destroyed) {
```

```js
// line 163
  throw new ERR_METHOD_NOT_IMPLEMENTED('_transform()');
```

Empirically confirmed on the target runtime — **Node v24.18.0**, executed locally:

```
typeof Transform.prototype._flush     = undefined
typeof Transform.prototype._transform = function
typeof Readable.prototype._read       = function

new Transform().write('x')
  → Error [ERR_METHOD_NOT_IMPLEMENTED]: The _transform() method is not implemented { code: 'ERR_METHOD_NOT_IMPLEMENTED' }

new Transform({ transform(c,e,cb){cb(null,c)} }).end('x')
  → ends cleanly; absent _flush is a silent no-op
```

VERIFIED (empirical, Node v24.18.0 — the same major the target project runs).

**Read the shape of that decision, because it is the answer to the brief's "name that fork":**

| Method | Base implementation | Absent means |
| --- | --- | --- |
| `_transform`, `_read` | **exists on the prototype and throws** `ERR_METHOD_NOT_IMPLEMENTED` | **a bug in the implementer** — fail loudly, name the method in the message |
| `_flush`, `_construct` | **does not exist**; call site is `typeof this._flush === 'function'` | **a legitimate configuration** — no-op |

Note that line 127 is `if (typeof this._flush === 'function')` — **Node core writes the exact
`if (adapter.method)` the brief calls a problem.** It is not a problem *there*, because the semantics
of omission are stated in the published docs next to the method ("Custom Transform implementations
may implement…"). **The defect in the motivating code is not the `if`; it is the undocumented
`else`.** That reframing matters: you do not have to delete the branch to fix the contract.

### 5.3 What `{...defaults, ...adapter}` buys and costs

**Buys** (analysis, grounded in the mechanics above rather than quoted from a source — marked as
reasoning, not citation):

- The fallback is a **real, readable, testable function** in exactly one place, next to the contract.
- The caller loses every branch: `adapter.prepareLessonPage(page)` unconditionally.
- The default becomes **unit-testable in isolation**, and can be covered by the same conformance
  suite that covers real adapters (§7.3).
- Type/JSDoc tooling sees a total object, so autocomplete and `@satisfies` checks work uniformly.

**Costs:**

- **The host can no longer distinguish "omitted" from "explicitly opted into the default."** After
  the spread, `Object.hasOwn(merged, 'prepareLessonPage')` is `true` either way. If you ever need
  that distinction (diagnostics — "adapter X does not implement Y"; capability listing; conformance
  reporting), you must capture it **before** merging. Practical mitigation: keep the raw adapter, and
  derive presence from it — `const declared = new Set(Object.keys(rawAdapter))` — then merge for use.
  This is cheap and worth doing from day one; retrofitting it later means auditing every call site.
- **You have committed to one default for all adapters**, where a null-return convention lets each
  adapter decline per call (§1.5). If any adapter needs "usually handle this, sometimes decline,"
  a defaults object is the wrong instrument.
- **Precedence bugs are silent.** `{...defaults, ...adapter}` with an adapter that has
  `prepareLessonPage: undefined` (a very easy accident with destructuring or conditional
  construction) **overwrites the default with `undefined`** and you get a `TypeError` at call time,
  not a fallback. Guard it: strip `undefined`-valued own keys before merging, or merge with an
  explicit loop that skips them. This is the single most likely way this pattern fails in practice.

### 5.4 THE FORK, named

> **A defaulted method that THROWS "unsupported" and one that returns a benign empty value are not
> two flavors of the same design. They encode opposite answers to: "is omitting this method a
> legitimate configuration, or a bug?"**

- **Benign default (no-op / identity / empty)** — omission is legitimate. Choose when the method is a
  genuine enhancement and the pipeline has a correct behavior without it. Precedents: Node's absent
  `_flush` (§5.2); Rollup's absent `first` hook (§1.5); Vite's absent `applyToEnvironment` meaning
  "active in all environments" (§2.3); LSP's `positionEncoding` defaulting to `'utf-16'` (§3.4).
- **Throwing default** — omission is a bug, or the pipeline genuinely cannot proceed. Choose when
  there is no correct behavior without the method. Precedents: Node's `_transform` /
  `_read` throwing `ERR_METHOD_NOT_IMPLEMENTED` (§5.2); Fastify's `getDecorator` throwing
  `FST_ERR_DEC_UNDECLARED` (§5.5); MCP's `-32021 MissingRequiredClientCapabilityError` (§4.2).

The three throwing precedents share a property worth copying: **each throws a named, coded, greppable
error that identifies the missing member.** `ERR_METHOD_NOT_IMPLEMENTED('_transform()')`,
`FST_ERR_DEC_UNDECLARED`, `data.requiredCapabilities`. A throwing default that says only
"not supported" throws away most of the value of throwing.

**Corollary that decides the design:** if a method's honest default is *throw*, then it is not an
optional method at all — it is a **required** method that you have failed to require. Move it to the
required set and validate at adapter-registration time. This collapses the hard case and leaves the
optional set genuinely optional, which is the state in which a benign documented default is always
the right answer.

### 5.5 Fastify — declared dependencies + a throwing accessor + presence-query API

Source: <https://fastify.dev/docs/latest/Reference/Decorators/>.

- **Declared dependencies, checked at boot.** VERIFIED `[EXACT]`: "The `dependencies` parameter is an
  optional list of decorators that the decorator being defined relies upon. This list contains the
  names of other decorators." Signature VERIFIED `[EXACT]`: `decorate(name, value, [dependencies])`,
  `decorateReply(name, value, [dependencies])`, `decorateRequest(name, value, [dependencies])`.
  Requirements are **declared as data and verified early**, not discovered at call time — the same
  move as a capability flag, aimed at requirements rather than provisions.
- **Throwing accessor.** VERIFIED `[EXACT]`: "`getDecorator(name)` — Used to retrieve an existing
  decorator from the Fastify instance, Request, or Reply. **If the decorator is not defined, an
  `FST_ERR_DEC_UNDECLARED` error is thrown.**" And VERIFIED `[EXACT]`: "// This will throw
  `FST_ERR_DEC_UNDECLARED` due to typo in decorator name" — the documented motivation is
  **typo-catching**, which is precisely the failure mode `if (adapter.prepareLessonPage)` cannot
  catch: a misspelled optional method silently takes the fallback forever.
- **Presence query as first-class API.** VERIFIED `[EXACT]`: "`hasDecorator(name)` — Used to check for
  the existence of a server instance decoration"; likewise `hasRequestDecorator`,
  `hasReplyDecorator`.

Fastify's answer is the *hybrid*: presence-sniffing is legitimate and gets a named API, **and** a
strict accessor exists for when absence is an error, **and** requirements are declared as data and
checked at boot. All three coexist because they answer different questions.

**The typo point is worth pulling out.** It is the strongest single argument against bare
`if (adapter.method)` in a small contract, and it is independent of scale: with duck typing,
`prepareLessonpage` (lowercase p) is not an error — it is silently "the adapter opted out." Any of
the three fixes below closes it: a defaults merge with a key-set validation, a declared flag checked
against the method, or a conformance test asserting the exact key set.

---

## 6. NULL OBJECT — canonical citation, intent, and where it is wrong

### 6.1 Bibliographic citation

VERIFIED `[EXACT]` — <https://www.informit.com/store/pattern-languages-of-program-design-3-9780201310115>:

> "Table of Contents
> Preface.
> I. GENERAL PURPOSE DESIGN PATTERNS.
> **1. Null Object, Bobby Woolf.**
> 2. Manager, Peter Sommerlad. …"

and VERIFIED `[EXACT]` from the same page: "Pattern Languages of Program Design 3 — By Robert C.
Martin, Dirk Riehle, Frank Buschmann — Published Oct 7, 1997 by Addison-Wesley Professional …
ISBN-13: 978-0-201-31011-5".

So: **Bobby Woolf, "Null Object", in *Pattern Languages of Program Design 3*, eds. Robert C. Martin,
Dirk Riehle, Frank Buschmann, Addison-Wesley Professional, 1997, chapter 1.** VERIFIED `[EXACT]`.

### 6.2 Intent — flagged as NOT verbatim-verified

The commonly circulated intent is "to encapsulate the absence of an object by providing a
substitutable alternative that offers suitable default do-nothing behavior." **UNVERIFIED as a
verbatim quotation.** I located a PDF of the paper at
<https://ingenieria-de-software-i.github.io/assets/bibliografia/objeto-nulo-bobby-woolf.pdf> and
extracted its content streams locally; the file is **page images with no text layer**, so no verbatim
text could be recovered. I am therefore not presenting an intent sentence inside quotation marks.
Cite the chapter (§6.1), and paraphrase the intent in your own words rather than quoting.

### 6.3 Fowler — premise VERIFIED

The brief states that Fowler's *Introduce Special Case* subsumes *Introduce Null Object*. **VERIFIED
`[EXACT]`** — <https://refactoring.com/catalog/introduceSpecialCase.html> carries, as structured
catalog metadata on the entry itself:

> "**aliases** Introduce Null Object"

and the entry's before/after sketch, VERIFIED `[EXACT]`:

```
if (aCustomer === "unknown") customerName = "occupant";
```
→
```java
class UnknownCustomer {
  get name() {return "occupant";}
```

Note what that sketch is: a **conditional at the call site**, replaced by **a named object carrying
the default behavior**. It is a one-line statement of the exact refactoring this design pass is
considering — `if (adapter.prepareLessonPage) … else …` becomes a defaults object with a real
`prepareLessonPage`. The canonical catalog entry is directly on point.

### 6.4 Where Null Object is WRONG

Stated as reasoning, grounded in the fork of §5.4 — not quoted from Woolf:

**A Null Object is wrong exactly when absence is a real error, because its whole mechanism is to make
absence indistinguishable from presence.** Concretely, avoid it when:

- Omission indicates a **misconfiguration or typo**. The Fastify `FST_ERR_DEC_UNDECLARED` motivation
  (§5.5) is the documented instance: a silent default converts a typo into permanent wrong behavior
  with no signal.
- The method's absence means **the pipeline's output is silently degraded rather than equivalent**.
  A "do-nothing" `prepareLessonPage` that yields an unprepared page is only correct if an unprepared
  page is a correct input downstream. If it is merely *tolerated*, the Null Object has laundered a
  defect into a normal-looking result.
- The host needs to **report** on adapters (which support what). A Null Object erases the
  distinction; you must retain the pre-merge key set to get it back (§5.3).

Node core's split (§5.2) is the disciplined resolution: Null-Object the genuinely optional
(`_flush`), and install a **loudly throwing** stand-in for the genuinely required (`_transform`) —
which is a Null Object in structure (always present, uniform call site) but the opposite in
semantics.

---

## 7. CAPABILITY FLAGS AS DATA vs CAPABILITY AS STRUCTURE

### 7.1 Which do mature systems use?

| System | Mechanism | Marker |
| --- | --- | --- |
| LSP | **Declared data.** `ServerCapabilities` / `ClientCapabilities`, `?` + `boolean \| Options`, exchanged at `initialize` | VERIFIED §3 |
| MCP (2026-07-28) | **Declared data.** `ClientCapabilities` per request in `_meta`; server capabilities via `server/discover` | VERIFIED §4 |
| Rollup | **Structure.** `if (hook)` at dispatch, conflated with null returns | VERIFIED §1.5 |
| Vite | **Both.** Structure for hooks; declared data for `enforce`, `apply`, `sharedDuringBuild` | VERIFIED §2 |
| esbuild | **Registration.** `build.onResolve({filter}, cb)` inside `setup` | VERIFIED §5.1 |
| Fastify | **Both.** `hasDecorator()` presence query + `dependencies` declared array + throwing `getDecorator` | VERIFIED §5.5 |
| ESLint | **Declared data,** enforced at runtime. `meta.fixable`, `meta.hasSuggestions` | VERIFIED §7.3 |
| Node streams | **Structure,** with documented per-method omission semantics and a throwing base for required ones | VERIFIED §5.2 |

**The split is not arbitrary and the boundary is crisp: every cross-process system in the table
declares; every in-process system sniffs or registers.** That is the whole finding of this section,
and it is the discriminator §8 uses.

### 7.2 The recognized reason to prefer declared data

Tied explicitly to §3.6: declared data buys the host the ability to reason about a participant
**without invoking it** — routing, UI enablement, scheduling, caching, reporting, version
negotiation. Where invocation is impossible (separate processes: LSP, MCP), too early (LSP forbids
requests before `initialize` — VERIFIED §3.2), or side-effecting, structural sniffing is not a
weaker option, it is **not an option**.

The corollary is the part usually left unsaid, and it is the one that governs this decision:
**in-process JavaScript has none of those constraints.** `typeof adapter.prepareLessonPage ===
'function'` is free, synchronous, side-effect-free, and exact. So the LSP argument for declared flags
**does not transfer on its own merits** to an in-process adapter. It transfers only if the host
acquires a reason to reason-without-calling — §8 enumerates them.

### 7.3 A flag can LIE — how systems close the gap

The failure mode: `supports: { prepareLessonPage: true }` with no such method (over-declaration), or
a method present with the flag `false`/absent (under-declaration).

**ESLint closes the under-declared direction at runtime, and documents the omitted-value default in
the same breath.** VERIFIED `[EXACT]` — <https://eslint.org/docs/latest/extend/custom-rules>:

> "`fixable`: (string) Either `"code"` or `"whitespace"` if the `--fix` option on the command line
> automatically fixes problems reported by the rule.
>
> **Important:** the `fixable` property is mandatory for fixable rules. **If this property isn't
> specified, ESLint will throw an error whenever the rule attempts to produce a fix.** Omit the
> `fixable` property if the rule is not fixable."

> "`hasSuggestions`: (boolean) Specifies whether rules can return suggestions (**defaults to `false`
> if omitted**).
>
> **Important:** the `hasSuggestions` property is mandatory for rules that provide suggestions. **If
> this property isn't set to `true`, ESLint will throw an error whenever the rule attempts to produce
> a suggestion.** Omit the `hasSuggestions` property if the rule does not provide suggestions."

and restated at the point of use, VERIFIED `[EXACT]`: "**Important:** The `meta.fixable` property is
mandatory for fixable rules. ESLint will throw an error if a rule that implements fix functions does
not export the `meta.fixable` property."

Three things to take from this, all directly applicable:

1. **`hasSuggestions` — "(defaults to `false` if omitted)" — is a declared-data capability flag whose
   absent-value default is documented on the property.** Same idiom as LSP §3.4 and MCP §4.4. Three
   independent mature systems, one idiom.
2. **ESLint enforces the flag where the lie is detectable for free**: the moment the rule *acts*
   beyond its declaration, throw. Cheap, exact, no test suite needed.
3. **It appears to close only ONE direction.** Under-declaration (does more than declared) throws —
   VERIFIED by the quoted text. Over-declaration (`fixable: "code"` on a rule that never fixes) is
   presumably inert — **UNVERIFIED**: every "Important" note in the docs is about *attempting* an
   undeclared action and none is about declaring an action never attempted, but silence is not a
   statement, and I did not test it. Treat the one-directional reading as the likely case, not an
   established one. The design point below does not depend on which way ESLint actually falls.

**Does a conformance test suite close it?** Partially, and it is worth being exact about the
boundary:

- **Over-declaration — yes, and cheaply.** A conformance test that asserts
  `for (const k of Object.keys(adapter.supports)) if (adapter.supports[k]) expect(typeof adapter[k]).toBe('function')`
  is a few lines in vitest and is total over the declared set.
- **Under-declaration — yes, symmetrically:** assert that every optional contract method present on
  the adapter has a truthy flag.
- **Behavioral conformance — no.** No test suite can verify that a method flagged `true` actually
  *does the thing*, short of behavioral fixtures per adapter — which is a different (and much larger)
  investment than closing the flag/structure gap.

So a conformance suite closes the **structural** lie completely, and does nothing for the
**semantic** one. That is a real limit, and it is the reason to prefer a design where **the flag and
the structure cannot disagree in the first place** — which is precisely what a single defaults object
gives you (there is only one channel), and precisely what adding a `supports` map alongside methods
gives up (two channels that must be kept in sync, plus the LSP static/dynamic-exclusivity class of
rule from §3.5).

---

## 8. RECOMMENDATION for a SMALL JS adapter contract (2–3 adapters today)

### 8.1 The discriminator is NOT adapter count

Answering "are LSP-style capability flags overkill?" by counting adapters is the wrong axis. The
evidence in §7.1 sorts cleanly on a different one:

> **Declared capability flags earn their keep exactly when the host must decide something BEFORE, or
> WITHOUT, calling the method. Everything else is served by an optional method whose omitted meaning
> is documented on the contract.**

LSP and MCP declare because their participants are across a wire — sniffing is *impossible* and the
client must route, enable UI, and negotiate versions before invoking (§3.6). Rollup, Vite, Node, and
Fastify sniff or register because they hold the object and can ask it anything, for free, at any
time (§7.2). Your adapters are in-process ESM objects. **You are structurally in the second group,
and would be at 3 adapters or 30.**

**So: LSP-style capability flags are overkill here — not because the contract is small, but because
nothing in the host needs to reason about an adapter without invoking it.** State that as the reason,
because the reason is what tells you when it stops being true.

### 8.2 The scale threshold — expressed as triggers, not a number

Adopt declared capability flags when **any one** of these becomes true. Each is a concrete
manifestation of "must decide before calling":

1. **Adapters cross a process, package, or network boundary** — a plugin loaded from a separate
   package published by someone else, a worker, a subprocess, anything where you hold a manifest
   before you hold an object. (This is LSP/MCP's actual reason, §3.6.)
2. **Something renders or routes on capability** — a CLI `--list-adapters` showing what each
   supports, a UI enabling an action, a scheduler picking an adapter by what it can do. Reporting
   forces the distinction that a defaults merge erases (§5.3).
3. **The capability set must be serialized** — written to a manifest, cached, diffed across versions,
   or sent anywhere. A method is not serializable; a flag is.
4. **Probing acquires cost or side effects** — the moment "just call it and see" means I/O, a
   network fetch, or a mutation.
5. **The optional set outgrows the contract file** — when a reader can no longer see every optional
   method and its documented default on one screen, the doc-comment strategy stops delivering
   discoverability, and you need a single enumerable place. (This is the only trigger that is
   *genuinely* about size, and it is about the size of the *optional surface*, not the adapter count.)

Until then, adding a `supports` map buys nothing and costs a second channel that can disagree with
the first (§7.3) — plus the LSP-style reconciliation rules that disagreement forces (§3.5).

### 8.3 Recommended shape

Two files. The contract is the single place an adapter author reads, and it contains the defaults as
real, readable, testable functions.

**Naming note, so this sketch composes with sub-question (e).** The required members below are the
contract's actual members as recorded in the sibling file `e-design-rule.md` in this directory —
`extractTranscript`, `extractHlsUrl`, `deriveLandingUrl`, `buildLessonUrl`, plus a third
`page`-taking method that the task brief left unnamed. **Their parameter shapes are deliberately
written neutrally here**, because (e) concludes that the three `page`-taking signatures leak the
incumbent Playwright implementation and must be re-derived. This sketch is about *optionality and
absent-method defaults only*; it takes no position on those signatures, and the `…` placeholders are
where (e)'s answer lands. `prepareLessonPage` is the optional exemplar from this task's own problem
statement; `normalizeCues` is marked inline as **illustrative only** — it exists solely to show a
non-identity default alongside an identity one, and is not a proposed member.

```js
// adapter-contract.js
// The contract for a source adapter. Optional members list their absent-method
// default alongside the member; the default is the real function in DEFAULTS below.

/**
 * @typedef {object} SourceAdapter
 *
 * @property {string} id
 *   Required. Stable identifier, used in logs and in adapter selection.
 *
 * @property {(courseUrl: string, cfg: SourceConfig) => string} deriveLandingUrl
 *   Required.
 * @property {(course: Course, lesson: Lesson, cfg: SourceConfig) => string} buildLessonUrl
 *   Required.
 * @property {(...) => Promise<TranscriptCue[]>} extractTranscript
 *   Required. Signature pending sub-question (e).
 * @property {(...) => Promise<string>} extractHlsUrl
 *   Required. Signature pending sub-question (e).
 *
 * @property {(page: LessonPage, cfg: SourceConfig) => Promise<LessonPage>} [prepareLessonPage]
 *   Optional. Given a lesson page, return the page to hand to extraction.
 *   IF OMITTED: the page is used unchanged (identity). Omit this whenever the
 *   source needs no pre-extraction preparation — omission is a supported
 *   configuration, not a gap.
 *
 * @property {(raw: string, cfg: SourceConfig) => TranscriptCue[]} [normalizeCues]
 *   Optional. ILLUSTRATIVE ONLY — present here to show a non-identity default.
 *   IF OMITTED: cues are parsed by `defaultCueParser` (see DEFAULTS.normalizeCues).
 */

/**
 * Absent-method behavior for every optional member of {@link SourceAdapter}.
 * This object IS the documentation of what omission means: read the function.
 * Every key here MUST correspond to an optional member above, and vice versa —
 * `adapter-contract.test.js` asserts that correspondence.
 *
 * @type {Required<Pick<SourceAdapter, 'prepareLessonPage' | 'normalizeCues'>>}
 */
export const DEFAULTS = Object.freeze({
  /** No preparation: extraction reads the page as delivered. */
  prepareLessonPage: async (page) => page,

  /** No source-specific cue shape: fall back to the shared parser. */
  normalizeCues: (raw) => defaultCueParser(raw),
});

/**
 * Required members. Absence here is a bug, not a configuration (§5.4 corollary).
 * Split by kind so the check is a real type check, not a presence check.
 */
const REQUIRED_METHODS = Object.freeze([
  'deriveLandingUrl',
  'buildLessonUrl',
  'extractTranscript',
  'extractHlsUrl',
]);

/**
 * Validate an adapter and return it with every optional member present.
 * Call once at registration. After this, callers never branch on method presence.
 *
 * @param {Partial<SourceAdapter>} adapter
 * @returns {Required<SourceAdapter> & { declared: ReadonlySet<string> }}
 */
export function defineAdapter(adapter) {
  const label = typeof adapter.id === 'string' && adapter.id ? adapter.id : '<unnamed>';

  if (typeof adapter.id !== 'string' || adapter.id === '') {
    throw new TypeError('Adapter is missing a non-empty string "id"');
  }
  for (const key of REQUIRED_METHODS) {
    if (typeof adapter[key] !== 'function') {
      throw new TypeError(
        `Adapter "${label}" is missing required method "${key}" (got ${typeof adapter[key]})`,
      );
    }
  }

  // Typo guard, narrowed: an optional member supplied under a near-miss name is
  // the failure `if (adapter.m)` cannot catch (Fastify's FST_ERR_DEC_UNDECLARED
  // motivation, §5.5). Only near-misses of KNOWN optional names are rejected, so
  // the contract stays open to additive extension. See the tradeoff in §8.5.
  const optionalNames = Object.keys(DEFAULTS);
  for (const key of Object.keys(adapter)) {
    if (optionalNames.includes(key)) continue;
    const nearMiss = optionalNames.find(
      (n) => n !== key && n.toLowerCase() === key.toLowerCase(),
    );
    if (nearMiss) {
      throw new TypeError(
        `Adapter "${label}" has member "${key}" — did you mean the optional member "${nearMiss}"?`,
      );
    }
  }

  // Own keys whose value is `undefined` must not clobber a default (§5.3).
  const supplied = Object.fromEntries(
    Object.entries(adapter).filter(([, v]) => v !== undefined),
  );

  // `declared` preserves what the author actually wrote, which the merge erases.
  return Object.freeze({
    ...DEFAULTS,
    ...supplied,
    declared: Object.freeze(new Set(Object.keys(supplied))),
  });
}
```

Call site, with no branch and no buried semantics:

```js
const prepared = await adapter.prepareLessonPage(page, cfg);
```

Adapter author's view — omission is now a positive, documented act:

```js
// adapters/acme.js
import { defineAdapter } from '../adapter-contract.js';

export default defineAdapter({
  id: 'acme',
  deriveLandingUrl: (courseUrl) => new URL('.', courseUrl).href,
  buildLessonUrl: (course, lesson) => `${course.base}/${lesson.slug}`,
  extractTranscript: async (...) => { /* … */ },
  extractHlsUrl: async (...) => { /* … */ },
  // prepareLessonPage omitted: Acme pages need no preparation (contract default: identity).
});
```

And the conformance test that keeps the two halves honest (§7.3), which is small enough to be
non-negotiable — this test, not the runtime guard, is what pins the exact optional key set:

```js
// adapter-contract.test.js
import { describe, it, expect } from 'vitest';
import { DEFAULTS, defineAdapter } from './adapter-contract.js';
import adapters from './adapters/index.js';

const REQUIRED_METHODS = ['deriveLandingUrl', 'buildLessonUrl', 'extractTranscript', 'extractHlsUrl'];

describe('adapter contract', () => {
  it('every optional member has a default, and every default is an optional member', () => {
    // Keep this list in sync with the @property [brackets] in the typedef.
    expect(Object.keys(DEFAULTS).sort()).toEqual(['normalizeCues', 'prepareLessonPage']);
  });

  it.each(adapters)('$id is total after defineAdapter', (adapter) => {
    for (const key of [...REQUIRED_METHODS, ...Object.keys(DEFAULTS)]) {
      expect(typeof adapter[key]).toBe('function');
    }
  });

  it('identity default leaves the page untouched', async () => {
    const page = { id: 'p1' };
    expect(await DEFAULTS.prepareLessonPage(page)).toBe(page);
  });

  it('rejects a near-miss optional member name (typo guard)', () => {
    const base = Object.fromEntries(REQUIRED_METHODS.map((k) => [k, () => {}]));
    expect(() => defineAdapter({ id: 'x', ...base, prepareLessonpage: () => {} }))
      .toThrow(/did you mean the optional member "prepareLessonPage"/);
  });

  it('rejects a required method supplied as a non-function', () => {
    const base = Object.fromEntries(REQUIRED_METHODS.map((k) => [k, () => {}]));
    expect(() => defineAdapter({ ...base, id: 'x', deriveLandingUrl: 'https://example.test' }))
      .toThrow(/missing required method "deriveLandingUrl" \(got string\)/);
  });
});
```

### 8.4 Why this shape, tied to the exhibits

- **The `IF OMITTED:` line in the JSDoc** is LSP's "If omitted it defaults to `'utf-16'`" (§3.4),
  ESLint's "(defaults to `false` if omitted)" (§7.3), MCP's "MUST treat … that omit the field as
  `complete`" (§4.4), and Vite's "if the hook is not used, the plugin is active in all environments"
  (§2.3). Four independent mature systems, one idiom, and it is the cheapest thing in this document.
  **If you adopt only one recommendation, adopt this one** — it fixes the stated defect on its own,
  even with the `if (adapter.m)` branch left in place, because the defect was the undocumented
  `else`, not the branch (§5.2).
- **`DEFAULTS` as a frozen object of real functions** is Fowler's *Introduce Special Case* (§6.3) and
  Node's benign-default fork (§5.2/§5.4): the fallback becomes a named, readable, individually
  testable function in one place.
- **`defineAdapter` throwing on missing required methods** is §5.4's corollary — if the honest
  default is *throw*, the method is required, so require it at registration rather than at call time.
  Node's `ERR_METHOD_NOT_IMPLEMENTED` and Fastify's `FST_ERR_DEC_UNDECLARED` are the precedents; both
  name the missing member in the message, and so does this (including the offending `typeof`).
- **The near-miss check** closes the typo hole that Fastify documents as `getDecorator`'s motivation
  (§5.5) and that bare `if (adapter.m)` cannot close — narrowed to case-insensitive collisions with
  known optional names, so the contract stays open to additive extension (§8.5).
- **The `undefined`-stripping filter** closes the silent-clobber failure of §5.3.
- **`declared`** preserves the one thing the merge destroys (§5.3) — at near-zero cost, and it is the
  seam through which trigger §8.2(2) is satisfied later without a refactor.
- **No `supports` map**, per §8.1: it would be a second channel that can disagree with the first
  (§7.3) with nothing currently needing to read it.

### 8.5 What this trades away — stated plainly

1. **Per-call opt-out.** Rollup's `first`-hook convention lets a plugin decline *this* call and handle
   the next (§1.5). A defaults object commits an adapter to one behavior for the whole run. If any
   adapter needs conditional participation, add a documented sentinel return (`return null` ⇒ caller
   falls back) and document *that* on the property — but note it reintroduces a second decline
   channel, so do it only for methods that need it.
2. **Registration ceremony.** Adapters must be constructed through `defineAdapter`, not exported as
   bare literals. That is a real constraint on authors and a real import in every adapter file. It
   buys the validation; it is not free.
3. **Host reasoning without invoking.** You get only what `declared` provides. Anything richer —
   sub-capabilities, options-with-support (`boolean | Options`, §3.4), version-conditional support —
   needs the declared-data design, which §8.2's triggers tell you when to build.
4. **Freezing.** `Object.freeze` blocks adapters that mutate themselves at runtime. That is intended,
   but it is a constraint worth knowing before it surprises someone.
5. **A hand-maintained list in the conformance test.** `expect(Object.keys(DEFAULTS).sort()).toEqual([…])`
   must be updated when an optional member is added. That is deliberate — it makes adding an optional
   method a conscious, reviewed act rather than an accident — but it is duplication, and it will
   occasionally be the thing that fails CI.
6. **Typo-guard strength vs additive extension — an explicit dial.** The narrowed near-miss check
   catches the realistic failure (`prepareLessonpage`) while leaving unrecognized keys alone, so the
   contract can be extended additively and `defineAdapter`'s own output (which carries `declared`)
   round-trips. The strict alternative — throwing on *any* key outside
   `REQUIRED_METHODS ∪ keys(DEFAULTS) ∪ {'id'}` — catches every typo including invented names, but
   **closes the contract to additive extension**: any adapter carrying a member the contract does not
   yet know about is rejected at registration, and the guard must be revised in lockstep with every
   contract change. Pick deliberately; the conformance test pins the exact key set either way, so the
   strict runtime form buys only earlier failure, not more coverage.

---

## 9. Claim ledger

| # | Claim | Marker | Source |
| --- | --- | --- | --- |
| 1 | Rollup plugin = object with "one or more of the properties…" | VERIFIED `[EXACT]` | <https://rollupjs.org/plugin-development/> |
| 2 | Rollup docs never state absent-hook behavior for the five sampled hooks | VERIFIED | ibid., full read of each section |
| 3 | `load`: "Returning `null` defers to other load functions…" | VERIFIED `[EXACT]` | ibid. |
| 4 | `renderChunk`: "Returning `null` will apply no transformations." | VERIFIED `[EXACT]` | ibid. |
| 5 | `transform`: "If `null` is returned **or the flag is omitted**…" | VERIFIED `[EXACT]` | ibid. |
| 6 | `first` / `sequential` / `parallel` / `async` definitions | VERIFIED `[EXACT]` | ibid. |
| 7 | Hook kinds are machine-readable union types | VERIFIED `[EXACT]` | `src/rollup/types.d.ts` |
| 8 | `Plugin extends OutputPlugin, Partial<PluginHooks>` — optionality via mapped type, not `?` | VERIFIED `[EXACT]` | ibid. |
| 9 | `type NullValue = null \| undefined \| void` | VERIFIED `[EXACT]` | ibid. |
| 10 | Rollup conflates absent with null: `if (hook)` filter + `if (result != null)` loop | VERIFIED `[EXACT]` | `src/utils/PluginDriver.ts` |
| 11 | Rollup has NO defaults-merging normalization step | REFUTED (premise) | ibid. |
| 12 | Vite 8 extends **Rolldown**, not Rollup | VERIFIED `[EXACT]` (premise qualified) | <https://vite.dev/guide/api-plugin.md> |
| 13 | `applyToEnvironment`: "if the hook is not used, the plugin is active in all environments" | VERIFIED `[EXACT]` | <https://vite.dev/guide/api-environment-plugins.md> |
| 14 | `enforce` omitted-case documented as a row in the ordering list | VERIFIED `[EXACT]` | <https://vite.dev/guide/api-plugin.md> |
| 15 | `apply` accepts a FUNCTION, not only `'build'`/`'serve'` | VERIFIED `[EXACT]` (premise qualified) | ibid. |
| 16 | `sharedDuringBuild: true` — boolean capability flag on a plugin object | VERIFIED `[EXACT]` | <https://vite.dev/guide/api-environment-plugins.md> |
| 17 | Vite `configDefaults` — not found in any docs page or the public export barrel | UNVERIFIED | see §2.5 for the five sources checked |
| 18 | LSP Capabilities rationale paragraph | VERIFIED `[EXACT]` | LSP 3.17 spec |
| 19 | "Clients should ignore server capabilities they don't understand" | VERIFIED `[EXACT]` | ibid. |
| 20 | "A missing property should be interpreted as an absence of the capability…" | VERIFIED `[EXACT]` | ibid. |
| 21 | `positionEncoding?` / `textDocumentSync?` — "If omitted it defaults to…" | VERIFIED `[EXACT]` | ibid. |
| 22 | `hoverProvider?: boolean \| HoverOptions` tri-state | VERIFIED `[EXACT]` | ibid. |
| 23 | Client must not send requests before `InitializeResult` | VERIFIED `[EXACT]` | ibid. |
| 24 | 2.x capabilities mandatory — "Clients cannot opt out of providing them." | VERIFIED `[EXACT]` | ibid. |
| 25 | `dynamicRegistration?: boolean`; static/dynamic exclusivity rule | VERIFIED `[EXACT]` | ibid. |
| 26 | MCP current spec version is 2026-07-28 | VERIFIED `[EXACT]` | <https://modelcontextprotocol.io/specification/> |
| 27 | MCP REMOVED the `initialize` handshake; capabilities are per-request in `_meta` | REFUTED (premise) | <https://modelcontextprotocol.io/specification/2026-07-28/changelog.md> |
| 28 | MCP: "A server MUST NOT rely on capabilities the client has not declared" + `-32021` | VERIFIED `[EXACT]` | <https://modelcontextprotocol.io/specification/2026-07-28/basic/index.md> |
| 29 | `server/discover` — servers MUST implement; `capabilities: {tools:{},resources:{}}` | VERIFIED `[EXACT]` | <https://modelcontextprotocol.io/specification/2026-07-28/server/discover.md> |
| 30 | Sub-capabilities `listChanged` / `subscribe` | VERIFIED `[EXACT]` | <https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle.md> |
| 31 | "Only use capabilities that were successfully negotiated" | VERIFIED `[EXACT]` | ibid. |
| 32 | esbuild plugins = `{ name, setup }`; capability via registration | VERIFIED `[EXACT]` | <https://esbuild.github.io/plugins/> |
| 33 | Node `_read` / `_transform` "must provide an implementation"; `_flush` / `_construct` optional | VERIFIED `[EXACT]` | <https://nodejs.org/api/stream.html> |
| 34 | `if (typeof this._flush === 'function' …)` and `throw new ERR_METHOD_NOT_IMPLEMENTED('_transform()')` | VERIFIED `[EXACT]` | `lib/internal/streams/transform.js`, v24.x |
| 35 | Empirical: absent `_transform` throws; absent `_flush` no-ops; `Transform.prototype._flush === undefined` | VERIFIED (empirical) | executed locally, Node v24.18.0 |
| 36 | Fastify `dependencies`, `hasDecorator`, `getDecorator` → `FST_ERR_DEC_UNDECLARED`, typo motivation | VERIFIED `[EXACT]` | <https://fastify.dev/docs/latest/Reference/Decorators/> |
| 37 | ESLint `hasSuggestions` "(defaults to `false` if omitted)"; `fixable` mandatory or ESLint throws | VERIFIED `[EXACT]` | <https://eslint.org/docs/latest/extend/custom-rules> |
| 38 | ESLint enforces only the under-declared direction (over-declaration is inert) | **UNVERIFIED** — the docs state the under-declared throws but say nothing either way about over-declaration; absence of a statement is not a statement of absence, and I did not test it. Inference from the quoted asymmetry only | ibid. |
| 39 | PLoPD3 ch.1 = "Null Object, Bobby Woolf"; AW, Oct 7 1997, ISBN 978-0-201-31011-5 | VERIFIED `[EXACT]` | <https://www.informit.com/store/pattern-languages-of-program-design-3-9780201310115> |
| 40 | Woolf's verbatim Intent sentence | UNVERIFIED | PDF at ingenieria-de-software-i.github.io is page images, no text layer |
| 41 | Fowler *Introduce Special Case* — "aliases Introduce Null Object" | VERIFIED `[EXACT]` (premise confirmed) | <https://refactoring.com/catalog/introduceSpecialCase.html> |
| 42 | Every cross-process system surveyed declares; every in-process system sniffs or registers | **INFERENCE** — not a fetched fact. Each row of §7.1 is individually VERIFIED; the generalization over them is mine, and it is drawn from an eight-system convenience sample, not an exhaustive survey | §7.1 |
