# Icons and illustrations

Read this when a web screen gains, swaps or resizes an icon, when icons from more than one place
sit together, or when an illustration goes on a page: a spot illustration in a tooltip, an empty
state, an onboarding screen, a feature section. The project's own icon library, illustration style
and conventions win over every rule here; suggest a change to them, never override them.

The CSS that sizes an icon beside its label is in `/user-interface:write-css`: its `text-and-media.md`
recipe `icon-sized-by-the-text-beside-it`. The names for what these rules describe (stroke weight,
optical center, meaning collision and the rest) are in `/user-interface:glossary`.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

These icon and illustration rules belong to other concerns, one home each: the accessible name of
an icon-only button is the `accessibility` concern; this file keeps the drawing of a favicon's mark
(section 2, item 12), while the favicon and app-icon files a page ships, and how a code-built
illustration is exposed to assistive tech, are the `marketing-pages` concern, and a favicon that
vanishes on a dark tab bar is the `theming` concern; a
decorative layer that swallows clicks is the `web-layout` concern; how an icon reads on a dark
surface is the `theming` concern; an icon or image whose missing dimensions shift the layout is the
`layout-stability` concern; animating a swap between two icons is the `motion` concern; emoji used
as icons and other default-looking decoration are the `generic-defaults` concern.

Contents: 1 icon sizes, 2 iconography, 3 illustrations.

## 1. Icon sizes

**Icon size system.** The defined sizes an icon is designed to appear at, typically 12, 16, 20,
24, and 48px. Each size is ideally drawn or adjusted for that specific context rather than scaled
from a single master.

Two worked examples of the stroke following the size. "Scaled weight" holds one
24-unit drawing and changes its `stroke-width` per size; "drawn per size" draws each size with its
own stroke and drops fine detail at the small sizes.

| Size | Typical place | Scaled weight: rendered stroke | Scaled weight: `stroke-width` in a 24-unit `viewBox` | Drawn per size: stroke, unit not given |
| --- | --- | --- | --- | --- |
| 12px | inline with text | 1.25px | 2.5 | 1.25 |
| 16px | button | 1.5px | 2.25 | 1.5 |
| 20px | navigation | not given | not given | 1.6 |
| 24px | toolbar | 2px | 2 | 1.75 |
| 48px | empty state | 3px | 1.5 | not given |

Both examples thin the stroke as the icon shrinks and thicken it as it grows, and their numbers are
not the same at every size, so treat them as a starting point and take the real values from the
project's icon library. A stroke width in these rules is the rendered one, not the attribute: a
24-unit drawing shown at 16px renders its `stroke-width="2"` at 1.33px, so measure what reaches the
screen. The two ways to get this wrong are the extremes: one rendered stroke width at every size (a
1px stroke at 12px almost vanishes and at 48px looks frail), and one master drawing scaled to every
size (the 12px and 16px icons turn into dense blobs and the 48px one turns heavy).

The ladder names the sizes an icon is drawn at. In CSS, an icon beside text takes its rendered size
from that text through recipe `icon-sized-by-the-text-beside-it`; choose the drawing whose size is
nearest the size it renders at.

**Audit: Suggestion.** An icon whose rendered stroke does not follow its rendered size: the same
rendered stroke at every size, or one drawing shown far from the size it was drawn for with that
drawing's stroke, such as a 24-unit drawing at 16px still rendering 2px or a 16px drawing shown at
48px. Items 1 and 7 of section 2 are graded by this line.

## 2. Iconography

1. Don't reuse a 24px icon's stroke width at 16px: thin the stroke to match the reduced scale, or
   the small version looks heavy.

   Section 1's Audit line grades this.

2. Snap icon coordinates to whole pixels. Half-pixel coordinates blur on 1x screens.

   **Audit: Suggestion.** A small custom icon whose path coordinates or `viewBox` offsets land on
   half pixels at the size it renders at.

3. Below ~12px, 1px-stroke icons disappear: swap to the filled variant at tiny sizes.

   **Audit: Important.** A 1px-stroke outline icon rendered below 12px.

4. Outlined vs filled for active/selected state is a trick question: either works. Consistency
   across the product is what matters.

   **Audit: Important.** Filled icons that mean active in one place and nothing in another, such as
   a tab bar where inactive tabs are filled too.

5. Optical centering beats mathematical centering: a play triangle centered mathematically in a
   circle looks left-heavy. Nudge it ~1px right. The `web-layout` concern grades this nudge.

6. Never mix two icon libraries on one surface, even similar-looking ones. Differences in stroke
   weight and corner radius compound across a card set.

   Hunt for: one component or screen importing icons from two packages, or a hand-drawn SVG beside
   library icons.

   **Audit: Important.** Two icon libraries on one surface.

7. Icons don't scale up: a 16px icon blown up to 48px keeps its now-spindly stroke. Redraw at 48px
   with a heavier stroke weight.

   An SVG scaled up scales its stroke with it, so the 48px version renders three times the 16px
   stroke and its detail turns coarse, as section 1 shows; the stroke stays thin only when it is
   held at one rendered width. Either way the fix is a drawing made for 48px. Section 1's Audit line
   grades this.

8. The floppy disk means nothing to anyone under 30. Ambiguous metaphors get a text label: a
   labeled "Save" button beats a bare icon.

   **Audit: Important.** An icon-only button whose metaphor is ambiguous, with no visible label.

9. Square stroke caps usually read as unfinished in UI contexts; default to round caps.

   In SVG that is `stroke-linecap="round"`, usually with `stroke-linejoin="round"` so the corners
   match the ends.

   **Audit: Suggestion.** Stroked icons with square or butt caps where the rest of the interface is
   rounded.

10. Union multipath icons into a single path with one fill. Multiple fills mean multiple things to
    restyle, theme, and break.

    **Audit: Suggestion.** A one-color icon built from several paths, each with its own `fill`.

11. Match icon stroke weight to adjacent text weight. A thin-stroke icon beside bold text looks like
    a mistake.

    **Audit: Suggestion.** A thin-stroke icon beside bold or semibold text.

12. Favicons need a simplified mark pixel-hinted for 16px. A full logo at favicon size is mush.

    **Audit: Suggestion.** The full logo, wordmark or detailed mark used as the 16px favicon.

13. One icon, one meaning: if a chevron means both "expand accordion" and "go to next page", users
    reliably learn neither. Use a distinct arrow variant for navigation.

    **Audit: Important.** One icon standing for two different actions in one product, such as a
    chevron that both expands a section and goes to the next page.

14. Icon pairs that differ only by 180° rotation (upload/download) are too subtle at a glance: add a
    second distinguishing signal. This matters doubly for colorblind users.

    A second signal is a label, a different shape (a tray under the download arrow, a cloud over the
    upload one) or a different position, not a second color alone.

    **Audit: Important.** Two icons with opposite meanings that differ only by rotation.

15. Alert shapes trick question: exclamation-in-circle typically reads as info/neutral,
    exclamation-in-triangle as warning, but conventions vary and both are used. Match your system's
    convention.

    **Audit: Suggestion.** An alert icon whose shape means one severity here and another elsewhere
    in the same product.

16. Give icon-plus-label buttons a 6–8px gap. With no breathing room they look collided.

    Recipe `icon-sized-by-the-text-beside-it` sets that gap as `0.5em`, which is 8px beside 16px
    text.

    **Audit: Suggestion.** An icon and its label with no gap, or a gap well under 6px.

17. Don't use the star for both "favorite" and "rating" in one product: the double meaning makes
    state ambiguous. Heart for favorite, star only for rating.

    **Audit: Important.** The star standing for both favorite and rating in one product.

## 3. Illustrations

An audit grades what the markup shows: an inline SVG's strokes, fills and colors, and the size it
renders at. Items 2, 4, 5, 6 and 9 are judged by looking at the screen, so their Audit lines are a
**Suggestion** for a person to check on screen rather than a grade read from code.

1. Match illustration stroke weight to the icon system. 2px illustration strokes beside 1px icon
   strokes reads as two different products.

   **Audit: Suggestion.** An illustration whose stroke is a different weight from the icons on the
   same screen.

2. Keep perspective consistent within a scene. Objects in one-point perspective mixed with a
   three-quarter-view character reads as uncanny.

   **Audit: Suggestion.** An illustration whose objects are drawn in different perspectives, for a
   person to check on screen.

3. Recolor stock/community illustration packs to the UI's color tokens. Dropped in with their own
   palette, they look bolted on.

   Recolor a pack's SVG only after someone has read it and committed it as static source markup;
   never insert fetched or uploaded SVG into the page with `innerHTML`. An SVG nobody has reviewed
   goes in an `<img>`; what a browser restricts there is in
   [MDN: SVG as an image, Restrictions](https://developer.mozilla.org/en-US/docs/Web/SVG/Guides/SVG_as_an_image#restrictions)
   (As of 2026-10-29, recheck when that section changes which limits it lists).

   **Audit: Suggestion.** An inline illustration with literal colors the project's color tokens do
   not hold.

4. Match illustration complexity to context: a tooltip gets a spot illustration, not a full
   narrative scene.

   **Audit: Suggestion.** A full scene in a small place such as a tooltip, for a person to check on
   screen.

5. The generic amorphous-blob-plus-character style signals "no budget or thought". A bespoke
   typographic treatment (or no illustration) beats generic.

   **Audit: Suggestion.** A generic blob-and-character illustration in the product, for a person to
   check on screen. On a marketing or brand surface the `generic-defaults` concern grades it.

6. Design negative space into the illustration itself. Forcing whitespace around it afterward looks
   like a clip-art drop-in.

   **Audit: Suggestion.** An illustration with no space of its own, padded out afterward, for a
   person to check on screen.

7. Illustrations don't scale up either: at 3× the intended size, strokes go thick and detail turns
   coarse. Redraw for the larger dimensions.

   **Audit: Suggestion.** An illustration shown far larger than it was drawn for.

8. Limit illustrations to ~3 colors. Six colors pulled from across the brand palette reads as
   indecisive; a reduced palette reads as intentional.

   **Audit: Suggestion.** An illustration with more than three colors.

9. Match the illustration's shadow/light direction to the UI's shadow direction. Opposing light
   sources create a subliminal wrongness.

   **Audit: Suggestion.** An illustration lit from the side opposite the interface's shadows, for a
   person to check on screen.
