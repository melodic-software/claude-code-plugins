# Theming and dark mode

Read this when a web app has, gains or is reviewed for a second color scheme: a dark mode, a theme
toggle, `dark:` variants, a `prefers-color-scheme` rule, `color-scheme`, `theme-color`, or a theme
provider. The project's own theme mechanism (its tokens, its theme attribute or class, its theme
provider) wins over every rule here; suggest a change to it, never override it.

Most apps are built in one color scheme and *have* a second one. The second gets a token flip, a
glance at the homepage, and ships with invisible cards, unreadable badges, and a logo that
disappears. This concern is a defect sweep of the other theme, not a redesign of it.

Other concerns hold the rest of dark mode, one home each. Which colors the dark theme takes (the
remap of a scale's roles, raised surfaces lighter than the base, opaque steps for layout borders and
dividers, desaturated brand colors) is the `color` concern, and so is text that has to read in both
themes. The low-opacity white ring that stands in for a shadow in dark mode, and the white image
outline, are the `shape-and-depth` concern. The theme on first paint is checked here and graded
under `layout-stability`, as the last paragraph of section 10 says. That a `::selection` pair
stays readable is the `typography` concern's rule; checking it in both themes is section 9.
Opening every route in the other theme on a real device is a check for a person in the audit's
launch scope.

The CSS for a single set of light and dark tokens is in `/user-interface:write-css`: its
`foundations.md` recipe `one-set-of-color-tokens-for-light-and-dark`.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

Contents: 1 which case you're in, 2 a single-theme app says so, 3 half a dark mode, 4 variables
flip at the root, 5 hardcoded colors, 6 elevation, 7 images and media, 8 third-party
surfaces, 9 browser chrome, 10 theme switches and first paint.

## 1. Which case you're in

First, from the project read, establish which case you're in:

```text
Does the app have a theme toggle, a `dark:` variant in use, or a
`prefers-color-scheme` rule?
├── No → single-theme app. Run sections 2 and 9 only.
└── Yes
    Is the second theme reachable by users (toggle, or OS setting honored)?
    ├── Yes → run every section
    └── No (dead `dark:` classes, no way to activate) → section 3, then section 9
```

## 2. A single-theme app says so

A dark-only app that never declares it gets white native scrollbars, light form controls, and a
white flash before the CSS loads. A light-only app that declares `light dark` (usually pasted in
with a boilerplate `<head>`) gets dark native controls and a dark canvas on any phone set to dark
mode, under a UI that was only designed light. Declare exactly the schemes that were designed.

```css
:root { color-scheme: light; }        /* light-only */
:root { color-scheme: dark; }         /* dark-only: native controls and scrollbars go dark */
```

Pasting `color-scheme: light dark` into a light-only app creates this bug. The same holds for the
`<meta name="color-scheme">` tag: a single-theme app sets it to that one scheme, and only a
two-theme app declares `light dark`.

- **Pointer**: MDN, `color-scheme`, what the used color scheme changes (canvas, scrollbars, form
  controls) and the `<meta name="color-scheme">` tag,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/color-scheme#syntax>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes which parts of the browser UI follow `color-scheme`, or
  what the meta tag prevents on load.

Hunt for: `<meta name="color-scheme">` and the CSS `color-scheme` property; a dark-only app with
neither; a light-only app declaring `light dark`.

**Audit: Important.** A dark-only app that declares no scheme, or a light-only app that declares
`light dark`.

## 3. Half a dark mode is worse than none

Some components have `dark:` classes and some don't, and the OS setting or a leftover toggle
activates it. The user gets dark cards on a white page with black text on the dark cards.

Hunt for: `dark:` utilities or `[data-theme="dark"]` rules present in some components and absent
in the layout, the inputs, or the text tokens; Tailwind's `darkMode` config set to `media` when the
app was only designed in light.

Whatever the Tailwind version, treat stray `dark:` classes as following the OS setting unless the
project ties the `dark` variant to a class or attribute selector. Read the project's CSS and config
for that tie before calling its dark theme unreachable.

- **Pointer**: Tailwind CSS, Dark mode, how the `dark` variant is tied to a selector,
  <https://tailwindcss.com/docs/dark-mode#toggling-dark-mode-manually>; the v3 page, the `darkMode`
  strategies, <https://v3.tailwindcss.com/docs/dark-mode#toggling-dark-mode-manually>; and v4's
  compatibility layer, which reads `darkMode` from a JavaScript config,
  <https://github.com/tailwindlabs/tailwindcss/blob/main/packages/tailwindcss/src/compat/dark-mode.ts>
- **As of**: 2026-10-29
- **Recheck trigger**: either page changes what the `dark` variant follows by default or renames the
  custom variant or the `selector` strategy, or the compatibility layer stops reading `darkMode`.

This is a decision, not a diff: either finish the theme or make it unreachable (remove the toggle,
set `color-scheme: light`, stop the `dark:` variant from firing). Put it on the human list with both
options and what each costs. Turning off a broken dark mode before launch is a legitimate choice.

**Audit: Blocking.** A half-built dark theme that users can reach, through a toggle or the OS
setting. Report it for a person with both options; never apply either one as a fix.

## 4. Dark mode flips variables, not classes

Define colors as a numbered scale of CSS variables and swap the values under the dark theme
selector. Don't scatter manual `dark:` overrides across components.

Use a numbered color scale as CSS variables and flip the values per theme:

```css
:root {
  --gray-1: oklch(0.985 0 none);
  --gray-2: oklch(0.97 0 none);
  --gray-12: oklch(0.205 0 none);
}

[data-theme="dark"] {
  --gray-1: oklch(0.205 0 none);
  --gray-2: oklch(0.239 0 none);
  --gray-12: oklch(0.985 0 none);
}
```

In Tailwind projects, do not hand-write `dark:` color overrides per component. Point utilities at
the variables and let the theme flip do the work:

```css
/* Good: variables flip automatically */
.button {
  background: var(--gray-12);
  color: var(--gray-1);
}

/* Avoid: manual overrides everywhere */
.button {
  @apply bg-gray-900 dark:bg-gray-100;
}
```

Which instruction wins: the project's existing theme mechanism first. With none, the
`/user-interface:write-css` recipe `one-set-of-color-tokens-for-light-and-dark` (one set of
`light-dark()` tokens switched through `color-scheme`) wins over the value swap
shown above. Which step each role takes in the dark theme is the `color` concern. This rule keeps
one thing whatever the mechanism: the flip happens once, at the theme root, never per component.

Hunt for: `dark:` overrides sprinkled through every component; component styles that set a color
for each theme instead of reading a variable.

**Audit: Important.** Per-component `dark:` color overrides, or a theme switched by classes on each
component, where the project could flip its colors once at the theme root.

## 5. Hardcoded colors don't flip

One `bg-white` on a dropdown, one `#fff` in an SVG, one `border-gray-200` on a card: each is a
bright rectangle in the dark theme. These are the most common dark-mode defects and the most
mechanical to fix.

Hunt for: raw hex / `rgb()` / `white` / `black` in component styles; Tailwind palette classes
(`bg-white`, `text-gray-900`, `border-gray-200`) in a project that has semantic tokens; inline
`fill="#000"` / `stroke="#111"` in SVG icons; `<img>` logos with baked-in dark text.

Fix: point each at the project's existing token. Icons use `currentColor` so they follow the text:

```html
<svg fill="none" stroke="currentColor">…</svg>
```

Never scatter new per-component `dark:` overrides to patch these. If the project flips a numbered
variable scale at the theme root, the fix is using the variable (section 4). A raster logo with
dark text needs a second asset or an SVG; that's the human list.

A raw hex in place of a semantic token, an SVG `fill="#000"` included, is graded once, under the
`color` concern. The finding here is the value that stays put when the theme flips: a palette
class, a `white` or `black` keyword in a style or an SVG `fill` or `stroke`, or a logo drawn for one
background.

**Audit: Important.** A palette class or color keyword, in a style or an SVG fill or stroke, that
stays the same in both themes and shows as a bright or invisible patch in the second one.

## 6. Elevation survives the dark theme

Shadows that vanish on a dark surface, and the single low-opacity white ring that replaces them,
are the `shape-and-depth` concern; it grades the finding. This concern only finds where the dark
value goes.

Hunt for: `box-shadow` tokens with no dark-theme value; cards and popovers with shadow-only edges;
`shadow-*` utilities with no dark counterpart.

If the project has shadow tokens, add the dark value at the token. If every component hand-writes
its shadow, that's a bigger job; list the surfaces that disappear and name the `shape-and-depth`
concern.

## 7. Images and media work on both backgrounds

A transparent PNG screenshot with dark text, a diagram drawn for a white page, a product shot with
a white matte: each is wrong on the other background.

Hunt for: transparent PNG / SVG assets containing text or dark linework; screenshots of the app's
light UI used on a dark marketing page; embedded charts with hardcoded axis colors; favicons that
vanish on a dark tab bar.

```html
<picture>
  <source srcset="/diagram-dark.svg" media="(prefers-color-scheme: dark)" />
  <img src="/diagram-light.svg" alt="…" width="800" height="400" />
</picture>
```

That works when the theme follows the OS. With a class-based toggle, render both and hide one by
theme class. A missing second asset can't be invented; flag it. A person supplies it, from the
human list.

**Audit: Important.** An image, diagram, chart or favicon that is unreadable or vanishes on the
other theme's background.

## 8. Third-party surfaces follow the theme

The app goes dark and the embedded pieces don't: a white code block, a white Stripe element, a
white chat widget, a light syntax theme, a map, a CAPTCHA.

Hunt for: syntax highlighter themes (Shiki / Prism) configured with one theme; payment, auth, and
support widgets with an `appearance` / `theme` option left at default; iframes.

Shiki takes a theme per scheme (`themes: { light, dark }`); Stripe Elements, Clerk, and most widgets
take an appearance option. Pass the app's resolved theme through.

Shiki's two themes also need a short CSS rule that switches them, keyed to the same media query or
class the app switches on.

- **Pointer**: Shiki, Light/Dark Dual Themes, the switching CSS,
  <https://shiki.style/guide/dual-themes#query-based-dark-mode> and
  <https://shiki.style/guide/dual-themes#class-based-dark-mode>; Stripe
  Elements Appearance API, themes, <https://docs.stripe.com/elements/appearance-api#theme>; Clerk,
  themes, dark theme,
  <https://clerk.com/docs/react/guides/customizing-clerk/appearance-prop/themes#dark-theme>
- **As of**: 2026-10-29
- **Recheck trigger**: any of them renames its theme option (`themes`, `appearance.theme`) or its
  dark theme value.

**Audit: Important.** An embedded code block, widget or iframe that stays light in the dark theme.

## 9. Browser chrome follows the theme

`theme-color` per scheme, `color-scheme` on the root so native scrollbars, form controls, and
autofill match (section 2), a `::selection` color that's legible in both, and a favicon that survives
a dark tab bar.

The status bar and the browser chrome take their color from `theme-color`. One value means light
mode gets a dark bar or dark mode gets a white one. Give each scheme its own:

```html
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#ffffff" />
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0a0a0a" />
<meta name="color-scheme" content="light dark" />
```

Match the value to the color at the very top of your page: the header background, not the brand
color. In Next.js set it through the `viewport` export (`themeColor: [{ media, color }]`). If the
app switches theme with a class rather than the OS setting, update the tag from JavaScript on
toggle. For an installed PWA, `apple-mobile-web-app-status-bar-style` and the manifest's
`theme_color`/`background_color` are the same decision. Read the colors from the project's tokens.
Never invent them.

The `color-scheme` line in that block is for a two-theme app; a single-theme app follows section 2.
A single-theme app runs this section for the selection pair, autofill in a dark form and the
favicon on a dark tab bar; one `theme-color` is right there. Treat `theme-color` as a finish, not a
fix the theme depends on; which browsers apply it is in the MDN pointer below.

- **Pointer**: MDN, `<meta name="theme-color">`, the `media` attribute and browser compatibility,
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta/name/theme-color#media>;
  Next.js, `generateViewport`, `themeColor`,
  <https://nextjs.org/docs/app/api-reference/functions/generate-viewport#themecolor>; MDN, the
  manifest `theme_color` and the meta tag that overrides it per scheme,
  <https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Manifest/Reference/theme_color#description>;
  Apple, Safari Web Content Guide, "Changing the Status Bar Appearance",
  <https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html#//apple_ref/doc/uid/TP40002051-CH3-SW1>
- **As of**: 2026-10-29
- **Recheck trigger**: MDN's page changes its Baseline status or what `media` does, Next.js renames
  the `themeColor` field, the manifest page gains a per-scheme `theme_color`, or Apple retires the
  archived guide.

Autofilled inputs get the browser's pale yellow or blue background regardless of theme; if that
breaks a dark form, override it:

```css
input:-webkit-autofill {
  -webkit-text-fill-color: var(--gray-12);
  box-shadow: 0 0 0 100px var(--gray-2) inset;
}
```

Use the inset shadow, as above, rather than a `background-color` rule; the pointer says why.

- **Pointer**: MDN, `:autofill`, description,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/:autofill#description>
- **As of**: 2026-10-29
- **Recheck trigger**: the page stops saying the autofill background cannot be overridden, or drops
  the `:-webkit-autofill` alias.

**Audit: Suggestion.** In a two-theme app, one `theme-color` for both schemes; in any app,
autofilled inputs that keep a light background in a dark form. A `::selection` pair that fails on
one theme is graded once, under the `typography` concern, and a favicon that vanishes on a dark tab
bar once, under section 7.

## 10. Theme switches must not animate

Flipping themes with transitions enabled makes every color on the page tween independently. Each
component has its own transition duration, so a theme toggle animates every surface at a different
speed and the page ripples. Disable transitions for the swap, re-enable after paint:

```js
function setTheme(theme) {
  document.documentElement.classList.add('no-transitions');
  document.documentElement.setAttribute('data-theme', theme);
  // Re-enable after paint (double rAF)
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      document.documentElement.classList.remove('no-transitions');
    });
  });
}
```

```css
.no-transitions,
.no-transitions * { transition: none !important; }
```

```jsx
// next-themes: no flash on load (it injects the blocking script), no color ripple on toggle
<ThemeProvider attribute="class" disableTransitionOnChange>
  {children}
</ThemeProvider>
```

Only when the project already uses `next-themes`. Match its existing `attribute`.

Under a Content Security Policy, pass the request's nonce through the provider's `nonce` prop;
never add `'unsafe-inline'` to `script-src` to let the provider's script run.

- **Pointer**: next-themes README, the `ThemeProvider` props (`attribute` and its default,
  `disableTransitionOnChange`, `nonce`), <https://github.com/pacocoursey/next-themes#themeprovider>
- **As of**: 2026-10-29
- **Recheck trigger**: the README changes the `attribute` default, or renames
  `disableTransitionOnChange` or `nonce`.

Hunt for: a theme toggle with no transition suppression; `next-themes` `ThemeProvider` without
`disableTransitionOnChange`.

**Audit: Important.** A theme switch that animates every color at its own speed: a toggle with no
transition suppression, or a `next-themes` provider without `disableTransitionOnChange`.

Whether the right theme is on screen at first paint, before any switch: check it here, and grade it
under the `layout-stability` concern.
