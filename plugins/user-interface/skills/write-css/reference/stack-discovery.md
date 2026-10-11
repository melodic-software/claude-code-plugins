# Stack discovery

The detail behind the four-step process in SKILL.md. The steps run in order; a later step never
replaces an earlier one.

## Contents

- Step 1: detect
- Step 2: identify the stack and research
- Step 3: the stack checklist
- Step 4: verify the compiled output
- Browser targets and Baseline

## Step 1: detect

`<plugin-root>/scripts/detect.mjs --project <root> --config --user-config <file>` prints JSON. The
keys this skill reads:

| Key | What it tells you |
|---|---|
| `project.browserslist` | `{query, source}`: the project's own browser target and the file it came from, or null |
| `project.tokens` | token files found in the usual places; tokens defined elsewhere are yours to find |
| `project.docs` | design-system and style-guide documents |
| `project.lint` | `{stylelint, eslint_css, config_paths}`: which CSS linters the project configures, and where |
| `project.style_files` | the kinds of styling present: stylesheet kinds (`css`, `scss`, …), `css-in-js`, and component files with `<style>` blocks (`vue`, `svelte`, …) |
| `config.values` | the resolved `css` settings |
| `config.provenance` | the layer each value came from |
| `config.prose` | team and personal prose files; read them, they may hold saved stack-checklist answers |
| `config.home_error` | the convention home did not resolve, so the team and personal layers were not read: say so |

Detect does not find written conventions or the nearest component. Look for them yourself: a CSS
or style guide under `docs/`, the project's `AGENTS.md`, `CLAUDE.md` or `CONTRIBUTING`, comments at
the top of the main stylesheet, and the existing component closest to the one you are writing.

**Without detect** (no shell, no Write tool, or no `node`), read the same signals by hand:
`.browserslistrc` or `browserslist`, the `browserslist` and `stylelint` keys in `package.json`,
`.stylelintrc*`, `stylelint.config.*`, an ESLint config that loads `@eslint/css`, and the files that
define custom properties or a theme. Say that detect did not run, and treat every setting as its
plugin default unless a convention file in the project sets it.

## Step 2: identify the stack and research

Name the mechanism from evidence: the dependencies in the manifest, the style file kinds, how the
nearest component writes its styles, and the build config. Never keep a list of frameworks in your
head and pick from it; the evidence in this project decides.

Research only what the evidence leaves open, through the route SKILL.md step 2 names. Saved answers
in `config.prose` are a starting point, not a result: check each against the files before using
it.

## Step 3: the stack checklist

Answer each question for this project, in the reply, with the file that answers it.

1. **Where do styles live, and in what form?** A global stylesheet, per-component files, a scoped
   block inside a component, utility classes, style objects in script, inline styles. Write new CSS
   in the same form, never in a second one. A technique the form has no shorthand for is written
   the long way in that form (an arbitrary property, a raw declaration), never swapped for a
   breakpoint.
2. **How are styles scoped, and what does scoping change?** Whether selectors are rewritten (an
   added attribute, a hashed class, a shadow root), whether a rule reaches elements a child
   component renders, and how the stack reaches the global scope or a child on purpose.
3. **How are tokens defined and referenced?** Custom properties, a theme object, a utility config,
   preprocessor variables. Which file holds them, and the exact syntax to reference one.
4. **What decides the order rules apply in?** Cascade layers the project declares, import order,
   a specificity convention, and how `!important` is used today.
5. **What does the build do to modern CSS?** Which preprocessors and post-processors run, and
   whether they pass through, rewrite or drop at-rules such as `@layer`, `@container`, `@supports`,
   `@starting-style` and nesting, or convert color functions.
6. **Which lint rules and conventions govern?** The Stylelint or `@eslint/css` rules, the written
   conventions, and what the nearest component already does.

When an answer cannot be checked in the project or a source this run, mark it unverified, name what
would settle it (a file, a doc page, a build), and write the CSS following the patterns already in
the repo rather than a guess about the library.

`/user-interface:setup apply` can save these answers into the team prose for later runs.

## Step 4: verify the compiled output

Run it when question 2 or 5 says the build rewrites selectors or values. Build the project, or the
one file, and read the emitted CSS: the rewritten selector reaches the element, the at-rules
survived, the values came out as written. When nothing can be built here, say what to look for and
where (the built stylesheet, or the element's matched rules in browser devtools).

## Browser targets and Baseline

The target comes from `--target`, then `project.browserslist`, then `css.browser_target`, then
Baseline widely available. Read each technique's support status from its topic reference's pointer,
and the meaning of the Baseline labels from the record below. When the target includes a browser
without the feature, wrap it in `@supports` with a fallback that keeps the component usable, or
skip it, and name the feature and the target in the reply.

- **Pointer**: <https://developer.mozilla.org/en-US/docs/Glossary/Baseline/Compatibility#baseline_badges>
- **As of**: 2026-10-11
- **Recheck trigger**: the page changes what "widely available" or "newly available" means.
