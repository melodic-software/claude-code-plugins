# Generic defaults

Read this when a web screen looks generated, generic or templated, when an agent built the screen
and it is about to ship, or when a marketing page, dashboard or app screen has just been generated.
The project's own brand, tokens, components and existing screens win over every rule here; suggest a
change to them, never override them. The shared rule, ask whether each choice came from the project
or from habit, is step 2 of "Work in this order" in `../../principles.md`; this file holds what to
look for on a web screen and what to do about it.

Nobody can point at the one element that makes a screen look AI-generated. They recognize the
accumulation: indigo gradient, glass cards, emoji icons, centered hero, three feature boxes, each
choice defensible alone, and together a watermark. The cause is mechanical: a model reproduces the
statistically most common pattern in its training data, and it does so for every decision on the
page at once. Fifty median choices don't average out to a median design. They compound into a
recognizable one.

This is a pass over any generated interface, in two halves. First strip the tells. Then put a point
of view back in: this half is not optional, because a screen scrubbed of tells but containing no
opinionated choice is still generic, just more quietly. The second half applies to marketing and
brand surfaces; section 11 states its scope.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

Lines that belong to other concerns, one home each: generic headlines and other interface copy are
the plain-language rule in `../../principles.md`, and `/ai-slop:audit copy <source files>` audits
them; scroll fade-ins and hover scales are the `motion` concern; icon sets, sizes and
stroke weights are the `icons` concern; typeface selection and pairing, missing font weights,
heading wraps, typographic characters, casing in CSS and the `lang` attribute are the `typography`
concern; building a palette is the `color` concern, and so is the contrast a gradient headline
loses; banding, shadows versus borders and nested radii are the `shape-and-depth` concern; dark
mode surfaces are the `theming` concern; the framework's default page title and favicon are the
`marketing-pages` concern; alt text that is a file name is the `accessibility` concern.

Contents: 1 the pass, 2 subtract first, 3 color, 4 typography, 5 layout, 6 decoration, 7
iconography, 8 placeholder content, 9 fabricated proof, 10 dates, numbers and currency from the
locale, 11 looking designed by someone, 12 final audit.

## 1. The pass

1. Squint test first: could this screen belong to any of ten thousand other products? Find the
   elements that tie it to *this* product specifically. If the answer is "the logo", everything
   else is up for review.
2. Subtract before you restyle (see "Subtract first"). Half the tells on a generated screen are
   elements that shouldn't exist at all, and there's no point picking a better color for something
   you're about to delete.
3. Sweep what's left in order: color, then typography, then layout, then decoration, then
   iconography, then the copy on the screen, then motion. Color goes first because it's the loudest
   tell: a page can survive a common layout, but not indigo-to-purple.
4. Put a point of view back in (see "Looking designed by someone").
5. Final read: "What here would make a designer suspect a model built this?" Fix it. Repeat until
   the answer is nothing.

## 2. Subtract first

Agents have an additive bias, and it's the same one you've seen in code: the belt-and-suspenders
try-catch, the re-implemented utility, the plan with three fallback steps nobody asked for. In UI it
shows up as extra everything: a caption under a heading that restates the heading, an icon in front
of every label, a divider between sections that spacing already separates, a badge on the card, a
second CTA, a helper line under the input, a border on a surface that also has a shadow. The result
is a screen that looks better than most engineers would build by hand and is still bad, because
every element is competing and none of it was chosen.

So before restyling anything, walk every element on the screen (every icon, line, badge, caption,
container, and word) and ask one question: **what breaks if this is gone?** If the answer is
"nothing", delete it. Not "it adds visual interest", not "it fills the space": those are the reasons
the model put it there. Run the walk again after the first round; deletions expose each other,
because an element that survived round one was often only earning its keep by balancing something
you just removed.

This is the highest-leverage step in the whole pass. Deletion is free, it can't introduce new tells,
and every element that survives gets hierarchy for nothing: the fewer things on the screen, the more
each one reads as deliberate.

The shared rule, add the fewest elements that do the job, is step 3 of "Work in this order" in
`../../principles.md`; this section is how it plays out on a generated web screen.

Deleting an element changes the design, so on an existing screen a deletion is a proposal the user
confirms, not a silent edit.

**Audit: Suggestion.** An element whose removal breaks nothing: a caption that restates its heading,
an icon in front of every label, or a divider between sections that spacing already separates.
More than one visually primary button, and competing emphasis without a redundant element, are the
`web-layout` concern's findings, not this one.

## 3. Color

### Indigo is not the brand color

`bg-indigo-500`, violet, and the blue-purple family are the single strongest tell: models absorbed
them from years of Tailwind examples, and now every generated UI on earth defaults to them. Purple is
not banned; *unchosen* purple is. If the palette wasn't derived from the product's domain, brand, or
content, derive one (the `color` concern covers building it in OKLCH). A finance tool, a farming app,
and an AI startup should not share a hue by accident.

**Audit: Suggestion.** An indigo, violet or blue-purple primary that no brand token, brand asset or
project decision accounts for.

### One gradient per screen, chosen, or none

The purple-to-cyan wash, the gradient hero background, the gradient border, the gradient text all on
one page is decoration standing in for a decision. Gradients also band badly when they're this casual
(the `shape-and-depth` concern covers easing them). Keep at most one, give it a job, and build it from
the palette you actually chose.

**Audit: Suggestion.** More than one gradient on a screen, or a gradient whose stops are not colors
from the project's palette.

### Dark-and-neon is a costume

Dark-by-default with glowing borders and neon accents is the model's idea of "premium tech". Dark
mode is a real feature with real rules (shadows stop working, surfaces need their own logic; see the
`theming` concern), not an aesthetic shortcut. Choose the default theme from where and when the
product is used, not from vibes.

**Audit: Suggestion.** A dark default theme with glowing borders or neon accents that nothing about
the product's use explains.

## 4. Typography

### No gradient text

`bg-clip-text text-transparent bg-gradient-to-r` on the headline is the typographic equivalent of the
purple gradient, and it costs you contrast and legibility to boot. Headlines get a solid color with
real contrast.

Hunt for the search tokens `bg-gradient-to-r` and `bg-linear-to-r`, and for `bg-clip-text` with
`text-transparent`; the pointer below holds Tailwind's current utility names.

- **Pointer**: Tailwind CSS, `background-image`, "Adding a linear gradient",
  <https://tailwindcss.com/docs/background-image#adding-a-linear-gradient>
- **As of**: 2026-10-29
- **Recheck trigger**: Tailwind renames the linear-gradient utilities again or drops `bg-clip-text`.

**Audit: Suggestion.** A headline filled with a gradient (`background-clip: text` with transparent
text). The contrast it fails is counted once, by the `color` concern.

### The default stack is a shrug

Inter at `font-black tracking-tight`, centered, is what a model writes when nobody chose anything.
Inter is a fine typeface: as a decision, paired and sized deliberately, not as an absence of one.
Make one distinctive typographic choice per project (the `typography` concern covers selection and
pairing); it does more to de-slop a page than any other single change.

That choice belongs on marketing and brand surfaces. Which fonts application UI uses is the "Type"
line of `../web.md`, and when a fix may swap a typeface is the `typography` concern's scope rule.

**Audit: Suggestion.** On a marketing or brand surface, Inter or another stock face at its heaviest
weight with tight tracking, centered, where nothing in the project chose it.

## 5. Layout

### The hero every model builds

Pill badge ("✨ Announcing v2.0"), centered headline, one-line subhead, primary button plus "Learn
more", gradient orb behind it. Every element here is a statistical default, which is why the
assembly reads as generated even when each piece is executed cleanly. Break the template where the
content justifies it: lead with the actual product (a real screenshot, a live demo) instead of an
abstraction, left-align if the copy runs long, cut the badge unless there is genuinely an
announcement.

### Three cards, an icon, a heading, two lines

The icon-title-description grid is the model's answer to "features section" regardless of what the
features are. The tell isn't the grid: it's that the layout was chosen before the content. Let the
features dictate the form: one feature that matters gets a full-width treatment with a real
screenshot; six small ones get a compact list; unequal features get unequal space. Symmetry that the
content didn't ask for is the giveaway.

### Bento is the new three-card grid

The bento grid became the "I know the three-card grid is slop" alternative, which made it slop with
better kerning. Same rule: if the cells were sized before anyone knew what goes in them, it's
decoration.

**Audit: Suggestion.** The assembled template hero (announcement badge with no announcement,
centered headline, subhead, two buttons, a decorative orb), or a features grid or bento whose equal
cells the features' content does not explain.

## 6. Decoration

### Glassmorphism needs glass

`backdrop-blur` with a translucent fill makes sense when there is something meaningful behind the
surface: a photo, a video, layered content. Floating a frosted card over a flat dark background is
applying the effect without its reason, which is exactly how a model uses it.

### Nothing floats behind the hero

Blurred gradient orbs and animated blobs exist to fill space the design didn't know what to do with.
Delete them. If the background feels empty afterward, the foreground content is too weak: fix that
instead.

**Audit: Suggestion.** A `backdrop-filter` blur over a flat background, or a blurred orb or blob
whose only job is filling space.

### One depth cue per surface

Border, shadow, ring, *and* gradient on the same card is a model hedging. Pick the depth system
(shadows or borders, per the `shape-and-depth` concern) and apply it consistently. And stop
`rounded-2xl` from being the answer to every radius: radii come from a scale, and nested radii are
derived, not repeated.

**Audit: Suggestion.** Several depth cues (border, shadow, ring, gradient) stacked on one surface,
or one radius such as `rounded-2xl` on every surface size. Surfaces that do not share one elevation
system, and a nested radius that is not derived, are counted once, by the `shape-and-depth` concern.

## 7. Iconography

### Emoji are not icons

🚀⚡🔒✨ as feature markers is the fastest way to make a page look generated. Emoji render differently
on every platform, can't take your palette, and read as placeholder because that's what they are.
Use a real icon set (one set, one stroke width) or none; a features list without icons is more
honest than one with rocket ships. The project's own icon set is the real one when it has one, and
choosing the set and its stroke weight is the `icons` concern.

**Audit: Important.** An emoji used as a functional icon in product UI: on a button, in navigation,
as a status or as an input decoration. It renders differently on every platform.

**Audit: Suggestion.** Emoji used as feature markers or section decoration on a marketing page.

### Sparkles don't mean AI

The ✨ sparkle badge on every AI feature is already a cliché. If a feature being AI-powered matters
to the user, the copy says what it does; if it doesn't matter, the badge is noise either way.

**Audit: Suggestion.** A sparkle icon or badge standing in for a description of what an AI feature
does.

## 8. No placeholder content

Nothing here shows up as a bug. The app works. It just says "Lorem ipsum" on the pricing page.

You can delete a fake testimonial, but you can't write a real one. Missing real content goes on the
human list.

**Hunt for** (case-insensitive, across `src` and content directories):

<!-- spellchecker:off -->
```text
lorem|ipsum|dolor sit          placeholder text|your text here
John Doe|Jane Doe|Acme         example\.com|test@|foo@bar
TODO|TBD|coming soon|WIP       Untitled|New Page|My App
\$0\.00|\$99|XX|###            via\.placeholder|placehold\.co|picsum|unsplash\.it
```
<!-- spellchecker:on -->

Also: `href="#"` and `href=""` on links that were never wired up (footer columns and social icons
are the usual place).

A seeded demo in a docs example is fine. Vet each hit.

A link in the conversion path (CTA, signup, checkout) that goes nowhere is the `marketing-pages`
concern's finding; count it there, and every other unwired link here.

**Audit: Blocking.** Placeholder text, a placeholder name, address, price or image, or a link
outside the conversion path that was never wired up, on a public page.

**Audit: Important.** The same on a page behind sign-in.

## 9. No fabricated proof

"Trusted by 10,000+ developers" on an unlaunched product, a testimonial grid of stock-avatar quotes,
a logo wall of companies that never said yes: models generate social proof as a *layout*, filled with
invented content. This is the design equivalent of vague attribution in prose (`/ai-slop:audit`),
except worse: it's a lie in the interface. Real numbers, real quotes with real names, or cut the
section entirely. An empty spot where fake proof used to be is a stronger signal than the fake proof.

Agents generating a landing page invent the social proof to fill the template: "Trusted by 10,000+
teams", a five-star testimonial from "Sarah K., Product Lead", a logo wall of companies that aren't
customers, "99.9% uptime", "SOC 2 compliant". On a live site these are false claims, and the
compliance ones are legal exposure.

**Hunt for:** testimonial, stats, logo-wall, and trust-badge sections. For each number, quote, and
logo, find its source in the repo (a CMS entry, a data file, a commit by a human). No source means
it's a finding.

Never fix this by rewording. Remove the section or flag it; the user confirms which claims are real.

When building a page that asks for proof the project does not hold, leave the section out and ask
for the real numbers, quotes and logos; never invent them to fill the layout.

**Audit: Blocking.** A number, quote, logo, rating or compliance claim with no source in the
repository.

## 10. Dates, numbers and currency come from the locale

Dates, numbers, and currency formatted by hand (`${month}/${day}`, `"$" + price.toFixed(2)`) are
wrong for most of the world. Use `Intl.DateTimeFormat` / `Intl.NumberFormat` when the app serves more
than one locale; note it when it doesn't.

**Audit: Important.** A date, number or price formatted by hand in an app that serves more than one
locale.

## 11. Looking designed by someone

Stripping tells leaves a clean, mute screen. What separates designed from generated is evidence that
somebody made choices only this product would make:

- **Derive the palette from something real.** The product's domain, an existing brand artifact, the
  content's own colors. A palette with a reason survives the squint test; a tasteful-but-arbitrary
  one doesn't.
- **One distinctive type decision.** A display face with a point of view, an unusual size contrast,
  a deliberate pairing. One is enough; three is a costume party.
- **Show the actual product.** A real screenshot, real data, a working embed. Abstract illustration
  is what models reach for because they've never seen your product. You have. Real data on a
  public page means seeded or demo data shaped like real use, never customer records, and an
  embed never carries a signed-in session or a key.
- **Let content break symmetry.** An odd number of features, one oversized item, a section that's
  just a sentence. Asymmetry the content earns is the cheapest authenticity there is.
- **Repeat a signature.** One distinctive element (a corner treatment, a rule weight, a motif) used
  consistently beats ten borrowed ones used once. Consistency of an odd choice is what a point of
  view looks like from the outside.
- **Restraint is a feature.** The confident version of a screen usually has fewer effects than the
  generated one, not more. Deleting decoration is de-slopping; adding "personality effects" on top is
  re-slopping with extra steps.

This section applies to marketing and brand surfaces: landing pages, homepages, brand and campaign
pages. On application UI, the project's own system applied consistently is the point of view, and
the platform's system font stack is a deliberate default there, not a tell.

When the project has no look of its own for the surface, the aesthetic direction goes where the
`marketing-pages` concern routes it.

**Audit: Suggestion.** A marketing or brand surface with no choice a competitor couldn't copy: a
palette, type decision or signature that nothing in the product explains, or abstract illustration
where the product could be shown.

## 12. Final audit

Squint one last time and ask two questions. "What here would make a designer think a model built
this?" (you're checking for survivors: a leftover glow, an emoji that snuck back in, a gradient with
no job). And "name the one choice a competitor couldn't copy-paste" (if nothing on the screen
answers, the pass isn't done: go back to "Looking designed by someone").

The second question applies to marketing and brand surfaces, as section 11 does.
