# Marketing pages

Read this when the page is a marketing surface: a landing page, homepage, hero section, pricing
page, blog, documentation site or changelog. These are the pages a stranger sees first, the pages
that get shared, and the pages a crawler reads. The project's own pages, tokens and conventions win
over every rule here; suggest a change to them, never override them.

Marketing pages earn more animation budget than product UI (a visitor sees a landing page once, not
a hundred times a day), but the budget is still small, and most sites overspend it. The pages that
convert are fast, readable, and honest: content in the DOM, fonts that don't shift, motion that maps
to what the user is doing. Restraint is the house style here: skip the scroll theatrics, ship the
page pre-rendered, and spend your effort on the details visitors feel but never name. They get one
visit to make their case, so the failures here are different from product UI: the link preview with
no image, the page that performs at the visitor instead of answering them, the blog that's fetched
from the CMS on every request.

When implementing anything below, match the project's existing styling system (Tailwind, plain CSS,
CSS Modules, CSS-in-JS) rather than introducing a new one; and match its framework conventions (the
examples use Next.js/React, but the principles are framework-agnostic).

**Visual direction.** When the project has no look of its own for the page (no tokens, no brand, no
existing screens to match), the aesthetic direction (type pairing, palette, the hero's composition)
goes to `/frontend-design:frontend-design` when it is installed; `/user-interface:design` routes it
there. Without it, the rules in this file and the sibling concerns still stand on their own. Making
a marketing or brand surface look designed rather than generated is the `generic-defaults` concern,
with the shared rule in `../../principles.md`; this file does not restate it.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

## Contents

- [1. Core principles](#1-core-principles)
- [2. Motion follows the visitor](#2-motion-follows-the-visitor)
- [3. Every public page has a title, a description and a preview](#3-every-public-page-has-a-title-a-description-and-a-preview)
- [4. Crawlers find the real pages, and the icons are the product's](#4-crawlers-find-the-real-pages-and-the-icons-are-the-products)
- [5. Heroes don't shift or overflow](#5-heroes-dont-shift-or-overflow)
- [6. Header navigation](#6-header-navigation)
- [7. Calls to action](#7-calls-to-action)
- [8. The conversion path works end to end](#8-the-conversion-path-works-end-to-end)
- [9. Documentation sites](#9-documentation-sites)
- [10. Blogs and changelogs](#10-blogs-and-changelogs)
- [11. Code-built illustrations](#11-code-built-illustrations)
- [12. Analytics and consent are wired, once](#12-analytics-and-consent-are-wired-once)

## 1. Core principles

1. **Motion must map to user input.** No scroll-triggered fade-ups, no scroll hijacking, no parallax
   that isn't 1:1 with scroll, no auto-advancing carousels. If the user didn't cause it, cut it.
2. **Intro animations play once per session.** Gate them with `sessionStorage` so returning within a
   session skips them, and new sessions see them fresh.
3. **Pre-render everything.** Blog, docs, changelog: build-time generation with revalidation. Never
   fetch this content at request time.
4. **Kill layout shift at the source.** Preload fonts and above-the-fold images.
5. **Content lives in the DOM.** Hover-revealed nav submenus stay in the DOM, hidden while closed,
   not conditionally rendered: crawlers and assistive tech need the real markup.
6. **CTAs know who's looking.** Logged-out visitors get "Get Started"; logged-in users get "Go to
   Dashboard".
7. **Docs are for copying.** Every code snippet gets a copy button; every page is exportable as
   markdown; every concept gets a visual example.
8. **Blogs and changelogs are feeds.** Ship RSS, balance headings.

Principles 3 and 4 are implemented and checked in their own concerns: font preloading in
`layout-stability`, image preloading and static generation with revalidation in `web-performance`;
a finding there is counted once, not again here. Where the project already has a font loading
strategy, that strategy wins over principle 4, as it does in the `typography` concern. Fabricated proof on a marketing page (invented logos, testimonials, user counts) is the
`generic-defaults` concern's. What to animate, how long and with which easing, and reduced motion
are the `motion` concern's.

## 2. Motion follows the visitor

Every section fading up as it scrolls into view, scroll hijacking, parallax that isn't 1:1 with
scroll, an auto-advancing carousel. All of these move without the user asking, and the page feels
like it's performing at the visitor. Scroll-triggered reveals also hide content from anyone who
scrolls fast, prints, or arrives with JavaScript still loading.

Hunt for: `whileInView`, `useInView`, `IntersectionObserver` driving opacity or translate on content
sections; AOS / ScrollReveal / GSAP ScrollTrigger on entrances; `wheel` listeners with
`preventDefault`; `scroll-snap` on the page itself; carousels with `autoplay` / `setInterval`.

Removing these changes the design, so it's an ask, not a silent fix. Two exceptions are defects and
get fixed outright: content that stays at `opacity: 0` when the observer never fires (no-JS, reduced
motion, print), and an auto-advancing carousel with no pause control (also a WCAG failure: moving
content that starts on its own and runs past five seconds needs a way to pause, stop or hide it).

- **Pointer**: WCAG 2.2, Understanding Success Criterion 2.2.2 Pause, Stop, Hide,
  <https://www.w3.org/WAI/WCAG22/Understanding/pause-stop-hide.html>
- **As of**: 2026-10-29
- **Recheck trigger**: a new WCAG version renumbers or rewords 2.2.2.

**Audit: Important.** A scroll-triggered reveal, scroll hijacking, parallax that isn't 1:1 with
scroll, or an auto-advancing carousel on a marketing page; raise it as an ask.

**Audit: Blocking.** Content left at `opacity: 0` when the observer never fires, or an
auto-advancing carousel with no pause control.

Intro animations (hero reveals, logo sequences) are fine, once. A hero entrance that replays on
every navigation back to the homepage is a tax. Gate it on `sessionStorage`, not `localStorage`, so
it plays again on a new visit but not on every internal navigation.

```jsx
useEffect(() => {
  if (sessionStorage.getItem("hasSeenIntro")) setSkipIntro(true);
  else sessionStorage.setItem("hasSeenIntro", "true");
}, []);
```

**Audit: Suggestion.** An intro animation that replays on every visit to the page in the same
session, or one gated on `localStorage` so a new visit never sees it.

## 3. Every public page has a title, a description and a preview

A page with no `<title>` shows its URL in the tab, in search results, and in every link preview. The
framework default ("Create Next App") is worse.

Hunt for: the root layout's `metadata` / `<head>`; public routes with no `metadata` export,
`generateMetadata`, or `<title>`; the same title on every route; dynamic routes (`/blog/[slug]`) with
static metadata.

```tsx
export const metadata: Metadata = {
  metadataBase: new URL("https://example.com"),
  title: { default: "Product", template: "%s · Product" },
  description: "…",
};
```

```tsx
// app/blog/[slug]/page.tsx
export async function generateMetadata({ params }) {
  const post = await getPost((await params).slug);
  return { title: post.title, description: post.excerpt };
}
```

The title template and per-route wiring are a fix. The words are content: take the title from the
page's `<h1>` and the description from existing copy (the hero subhead, the post excerpt). If
there's nothing to take them from, flag it; never invent the words. Set `metadataBase` in the root
layout so relative Open Graph image paths resolve to the production origin.

- **Pointer**: Next.js, `generateMetadata` and the `metadataBase` field,
  <https://nextjs.org/docs/app/api-reference/functions/generate-metadata#metadatabase>
- **As of**: 2026-10-29
- **Recheck trigger**: a Next.js release changes `metadataBase`, the title template, or the
  `Metadata` fields.

**Audit: Blocking.** A public route with no title and description, the framework's default title,
or one title shared by every route.

Launch day *is* people pasting the link into Slack, X, iMessage, and LinkedIn. With no Open Graph
image the link is a bare URL; with a broken one it's a gray box.

Hunt for: `openGraph` / `twitter` in metadata, or `og:image` / `twitter:card` meta tags; an
`opengraph-image` file in the app directory; an image path that doesn't exist in `public/`; an image
under the recommended link-share size (pointer below).

```tsx
// og.png's real width and height in pixels, at least the size the link-share pointer below recommends
const OG_WIDTH = …;
const OG_HEIGHT = …;

openGraph: { images: [{ url: "/og.png", width: OG_WIDTH, height: OG_HEIGHT }] },
twitter: { card: "summary_large_image" },
```

- **Pointer**: Meta for Developers, Images in link shares, "Requirements",
  <https://developers.facebook.com/docs/sharing/webmasters/images#requirements>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes its recommended link-share image size.

If no OG image exists in the repo, report it for a person to supply: it can't be invented. Blog
posts and docs pages get per-page images when the project already has a generator; otherwise the
site-wide one is fine. Leave a check for a person to run: paste the production URL into Slack and
iMessage and look at the preview.

**Audit: Important.** No Open Graph image, a path that doesn't resolve, or an image under the
recommended size.

**Audit: Blocking.** The same, when the task or the repository names a launch or announcement for
the page (a launch date, a launch checklist, a press or social post that links it).

## 4. Crawlers find the real pages, and the icons are the product's

Hunt for: `robots.txt` / `robots.ts` (missing, or a leftover `Disallow: /` from staging, which
de-indexes the whole site); `sitemap.xml` / `sitemap.ts` (missing, or listing `/proto`, `/lab`, and
auth-gated routes); `<link rel="canonical">` on pages reachable at more than one URL; `noindex` left
on from a staging config.

Leftover scaffolding routes go in `disallow` as a second layer; finding and gating them out of the
production build is `/user-interface:audit launch`. A `disallow` line is public and only a request
to crawlers: it names the path to anyone who reads `robots.txt` and blocks no visitor, so it never
stands in for gating a route out of the build or behind auth.

- **Pointer**: RFC 9309, Robots Exclusion Protocol, Section 3 "Security Considerations",
  <https://www.rfc-editor.org/rfc/rfc9309.html#name-security-considerations>
- **As of**: 2026-10-29
- **Recheck trigger**: an RFC obsoletes or updates RFC 9309.

**Audit: Important.** A missing robots file or sitemap, a sitemap listing scaffolding or auth-gated
routes, or no canonical on a page reachable at more than one URL.

**Audit: Blocking.** A leftover `Disallow: /` or a site-wide `noindex`.

Hunt for: the framework's default `favicon.ico`; no `apple-touch-icon` (the home-screen icon on iOS;
pointer below); no SVG icon; a manifest with default `name` / `short_name`.

- **Pointer**: Apple, Safari Web Content Guide, Configuring Web Applications, "Specifying a Webpage
  Icon for Web Clip",
  <https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html#//apple_ref/doc/uid/TP40002051-CH3-SW4>
- **As of**: 2026-10-29
- **Recheck trigger**: Apple retires the archived guide or documents a new home-screen icon lookup.

How the icon reads on a dark tab bar is the `theming` concern's. A missing icon asset is reported for
a person to supply.

**Audit: Important.** The framework's default favicon, no `apple-touch-icon`, or a manifest with the
default `name` / `short_name`.

## 5. Heroes don't shift or overflow

The hero is the LCP element and the first thing that can go wrong. Check it at 375px wide, where a
long word in a large size overflows the viewport. The rules underneath belong to their own concerns,
one home each: preloaded fonts to `layout-stability`, the hero image preloaded with dimensions to
`web-performance`, the hero's
`min-height` in small-viewport units to `touch`, and the balanced headline to `typography`.

**Audit: Important.** A hero that shifts on load or overflows the viewport at 375px wide.

## 6. Header navigation

Submenu content that appears on hover must still exist in the DOM at all times: hidden while closed
(the `hidden` attribute, as below), not mounted-on-hover. Header submenus that mount their content
on hover are invisible to crawlers and to assistive tech, and unreachable on touch. Render the
content always and keep it hidden while closed; hover, focus or a click on the button removes
`hidden` and sets `aria-expanded="true"`. Not a screen-reader-only class: that leaves the closed
menu's links in the tab order, focusable but unseen.

```html
<nav>
  <button aria-expanded="false" aria-controls="products-menu">Products</button>
  <div id="products-menu" class="submenu" hidden>…full content…</div>
</nav>
```

The CSS that shows and hides it is `/user-interface:write-css` recipe
`enter-and-exit-transitions-from-display-none`.

- **Pointer**: MDN, HTML `hidden` global attribute, "Description",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/hidden#description>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes how browsers treat an element in the hidden state.

Hunt for: `{isOpen && <Submenu />}` in the marketing header; submenus opened by `onMouseEnter` only,
with no click or focus path.

**Audit: Important.** A header submenu mounted only while open, or opened by hover with no click or
focus path.

## 7. Calls to action

CTAs adapt to auth state: a logged-in user being told to "Sign Up" is a dead end, or worse, lands on
a signup form that errors.

| State | CTA |
| --- | --- |
| Logged out | "Get Started" or "Sign Up" |
| Logged in | "Go to Dashboard" or "Open App" |

```jsx
<Button href={isLoggedIn ? '/dashboard' : '/signup'}>
  {isLoggedIn ? 'Go to Dashboard' : 'Get Started'}
</Button>
```

Resolve this on the client so the marketing page stays static; reading cookies in the layout to
decide the CTA opts the whole page out of static rendering (the `web-performance` concern). On the
client, read a signal that is safe for scripts to see, such as a signed-in hint cookie set at sign-in
or a session-status endpoint, never the session token; the session cookie stays out of reach of
scripts (`HttpOnly`). The label swaps after hydration, so reserve the CTA's space: the
`layout-stability` concern.

Hunt for: hero and header CTAs with a hardcoded `/signup` href in an app that has auth; client code
that reads the session token or a session cookie to pick the CTA.

**Audit: Important.** A CTA that does not switch its copy and destination with auth state in an app
that has auth.

**Audit: Blocking.** Client code that reads the session token to pick the CTA, or a session cookie
made readable to scripts for it.

## 8. The conversion path works end to end

The one flow that pays for the launch: landing → CTA → signup or checkout → first screen. Every link
in it resolves, the pricing on the page matches the pricing in checkout, the plan the button names
is the plan the checkout opens, and the post-signup redirect lands somewhere that exists.

Hunt for: CTA hrefs pointing at routes that don't exist; price strings hardcoded on the pricing page
vs the values in the billing config; test-mode payment keys or links (`buy.stripe.com/test_`, sandbox
checkout URLs); `mailto:` and social links with placeholder handles; waitlist and newsletter forms
whose `action` or handler posts nowhere. For Stripe test-mode keys, also search for the tokens
`pk_test_`, `sk_test_` and `rk_test_` (the key pointer below).

- **Pointer**: Stripe, API keys, "Key types", <https://docs.stripe.com/keys#obtain-api-keys>
- **As of**: 2026-10-29
- **Recheck trigger**: Stripe changes its key types or key prefixes.

Mismatched prices and test-mode payment links are blockers and go at the top of the report. You can
find them from code; you can't confirm the fix without the user, so state both values and ask which
is right.

**Audit: Blocking.** A broken link anywhere in the conversion path, a price on the page that differs
from the billing config, a publishable test key or a test payment link, or a signup form that posts
nowhere. A secret or restricted key, test or live, is the key rule's below.

**Only publishable keys go in client code.** A payment provider's secret or restricted key anywhere
in source, a committed config file or a client bundle is a secret exposure, in test mode as much as
live. For Stripe, search for the tokens `sk_live_`, `sk_test_`, `rk_live_`, `rk_test_` and
`sk_org_`; `pk_` marks the publishable key that may ship to the browser. Never write a live
key into source, a fixture or an example: the code reads it from a server-only environment variable
or the platform's secrets store, one the build never inlines into client code. In every report,
redact a key to its prefix and last four characters (`sk_live_…wxyz`), never the full value; for a
key, "state both values" above means the redacted forms. Rotating an exposed key is the user's
call: report it at the top and ask.

- **Pointer**: Stripe, API keys, "Protect your keys", <https://docs.stripe.com/keys#safe-keys>
- **As of**: 2026-10-29
- **Recheck trigger**: Stripe changes which key types are safe to expose, or its key prefixes.

**Audit: Blocking.** A secret or restricted payment key in source, a committed config file or a
client bundle.

## 9. Documentation sites

- **Copy button on every code snippet.** No exceptions: docs code exists to be pasted. The copy
  button's confirmation is the `states` concern's.
- **Every page copyable as markdown:** a "Copy as Markdown" button, plus `.md` URLs (e.g.
  `/docs/getting-started.md` returns raw markdown). This serves both humans and the LLMs
  increasingly reading your docs.
- **Visual examples everywhere.** Code alone isn't enough: show what the code produces. Let people
  see and ideally touch the result before they commit to using it.

**Audit: Suggestion.** A docs code snippet with no copy button, a docs page with no markdown export,
or a concept shown only as code.

## 10. Blogs and changelogs

- **RSS feeds exist** at predictable paths, linked from the `<head>` with
  `<link rel="alternate" type="application/rss+xml">`:

  ```text
  /blog/rss.xml
  /changelog/rss.xml
  ```

- **Dates in `<time datetime>`.**
- **Balance headings** so multi-line titles don't leave a stranded word. The wrap property and when
  to use it are the `typography` concern's.

**Audit: Suggestion.** A blog or changelog with no RSS feed or none linked from the `<head>`, dates
not in `<time datetime>`, or article headings left to default wrapping.

## 11. Code-built illustrations

Illustrations built from DOM elements need three things: the right exposure to assistive tech, no
text selection, and no pointer interference. No selection and no pointer interference are the
`web-layout` concern's decorative-layer rule; skip `pointer-events: none` only if the illustration
is interactive. Exposure is this file's. An illustration that carries information gets `role="img"`
and an accessible name:

```jsx
<div
  role="img"
  aria-label="Illustration showing data flow"
  className="illustration"
/>
```

A decorative one, which adds nothing the surrounding text does not say, is hidden from assistive
tech instead, and holds no focusable element (`aria-hidden` hides every descendant):

```jsx
<div aria-hidden="true" className="illustration" />
```

- **Pointer**: MDN, `aria-hidden`, "Description",
  <https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Attributes/aria-hidden#description>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes its guidance on decorative content or on focusable
  descendants.

**Audit: Important.** A code-built illustration that carries information with no `role="img"` and
accessible name, or a decorative one left exposed to assistive tech.

## 12. Analytics and consent are wired, once

Launch day traffic is the traffic you most want measured, and it's the day people discover the
analytics snippet was only on the homepage, or is loaded twice, or is blocking render.

Hunt for: analytics / tag scripts in the root layout vs a single page; the same snippet included
twice; third-party `<script>` without `async` / `defer` or the framework's script strategy; a
third-party script loaded from an origin other than its vendor's documented one, or, when the
project has a Content Security Policy, from an origin that policy does not list. A cookie
banner that pushes content down when it mounts is the `layout-stability` concern's; one that covers
the mobile CTA is the `touch` concern's.

Whether the site needs a consent banner is a legal decision, not a ship-check one. Note what tracking
exists and leave the decision to a person.

**Audit: Important.** An analytics snippet on only some public pages, loaded twice, or blocking
render; a third-party script from an unexpected origin or one the project's Content Security Policy
does not cover.
