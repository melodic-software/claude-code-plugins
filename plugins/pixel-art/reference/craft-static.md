# Static sprite craft

One rule per line, source in brackets. "(judgment)" marks a rule no source states.

Sources: [Saint11](https://saint11.art/blog/pixel-art-tutorials/) tutorial images
(`https://saint11.art/img/pixel-tutorials/<Name>.gif`), [Derek Yu 1](https://www.derekyu.com/makegames/pixelart.html),
[Derek Yu 2](https://www.derekyu.com/makegames/pixelart2.html),
[Slynyrd Pixelblog 1](https://www.slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes),
[Pixel Logic](https://archive.org/stream/pixel-logic-a-guide-to-pixel-art-michael-azzi/Pixel%20logic%20a%20guide%20to%20pixel%20art%20-%20Michael%20Azzi_djvu.txt) (Azzi),
[Lux AA](https://pixelparmesan.com/blog/anti-aliasing-fundamentals-for-pixel-artists),
[Lux dithering](https://pixelparmesan.com/blog/dithering-for-pixel-artists).

## Silhouette

- Order of work: silhouette, then details, then animation. [Saint11 Silhouette]
- Give the silhouette one strong recognizable element. [Saint11 Silhouette]
- Squint test: a few large clusters of light and dark must still emerge. [Derek Yu 1]
- Prefer clusters over orphan pixels; an orphan pixel is noise unless it is a deliberate detail.
  [Saint11 Fundamentals]
- Check the silhouette filled with one color before shading (judgment, follows Saint11).

## Outlines

- Full dark outline: cartoony, separates shapes, but segments harshly. [Derek Yu 1; Saint11 Outlines]
- Selective outline (sel-out): color the outline by the light, lighter toward the light, removed
  where the sprite meets lit negative space; use dark shadow colors, not black, for interior lines.
  [Derek Yu 1; Pixel Logic; Saint11 Outlines]
- Sel-out is the most common outline type. [Pixel Logic]
- Inner borders can be lighter than the outer outline. [Saint11 Outlines]
- No outline: saves space at very low resolution. [Saint11 Outlines]
- Default: sel-out for 24px and larger, full dark outline for 16px and smaller where readability
  over busy backgrounds matters (judgment).

## Light direction

- One light source, above and slightly in front; top and front bright, bottom and back shaded.
  [Derek Yu 1]
- Render main light, highlight, terminator, bounce light; projected shadows hard-edged, self-cast
  shadows soft. [Saint11 Shading]
- Default top-left, fixed across the whole asset set (judgment; no source mandates top-left).

## Ramps and hue shifting

- Shift hue as well as value along a ramp. [Saint11 Shading; Pixel Logic]
- Shift toward warmer hues as colors brighten ("positive hue shift"). [Slynyrd 1]
- Saturation peaks mid-ramp and never reaches 0 or 100; brightness rises steadily and rarely
  starts at 0. [Slynyrd 1]
- Never combine high saturation with high brightness. [Slynyrd 1]
- Faces of flat surfaces are mostly one solid color; compress bands so steps are hard to see.
  [Saint11 Shading]
- Ramp length 3-5 colors per material for sprites up to 32px (judgment).

## Pillow shading (avoid)

- Shading inward from the outline flattens form and looks blurry. [Derek Yu 2]
- AA or shading that follows the outline exactly produces pillow shading. [Pixel Logic; Lux AA]
- Fix: shade from the light direction, not from the edge. [Derek Yu 2]

## Banding (avoid)

- Parallel bands of equal length along an edge pull the eye to the seams. [Derek Yu 1; Lux AA]
- Over-AA creates banding. [Lux AA]
- Fix: stagger band edges, AA, or dither. [Pixel Logic; Derek Yu 1]

## Jaggies and line clean-up

- Reduce lines to 1px; remove doubles and unwanted corners. [Derek Yu 1; Saint11 Outlines]
- Keep staircase steps equal on straight lines; on curves, segment lengths grow or shrink
  steadily. [Derek Yu 1; Pixel Logic]
- Sharp corners are allowed on purpose for pointed shapes. [Saint11 Outlines]

## Manual anti-aliasing

- Place in-between colors at the corners where two segments meet. [Derek Yu 1]
- Longer segment, longer AA run. [Lux AA]
- Never AA the outer edge of a game sprite drawn over an unknown background. [Derek Yu 1]
- Ask whether each AA pixel is necessary; keep AA inside the sprite. [Lux AA]
- No AA at all below 16px (judgment).

## Dithering

- Use on large flat areas, rough textures, and 1-bit or low-color work. [Derek Yu 1; Lux dithering]
- Avoid on small or animated character sprites; it shimmers and reads as noise. [Lux dithering;
  Saint11 Fundamentals]
- Excess dithering makes a surface look rough. [Pixel Logic]
- When used, keep a regular pattern (checkerboard or ordered densities). [Saint11 Fundamentals;
  Lux dithering]

## Palette

- 32 colors is popular, 16 also common; beginners pick an existing palette. [Derek Yu 1]
- Every color needs its own identity; near-duplicates blend and get lost. [Derek Yu 2]
- [Lospec palette list](https://lospec.com/palette-list) filters by color count; start there.
- Lock the palette per project; every asset uses only its colors (judgment).
- Budget: 4-8 colors per small sprite including outline, drawn from the project palette
  (judgment).

## Grid size

No fetched source prescribes 16, 32, or 48 as a rule; everything here is judgment unless noted.

- Match the engine first: RPG Maker MZ tiles 48px, characters 48x48 (see `engine-layouts.md`);
  PICO-8 8x8.
- Smaller sprites put more weight on each pixel. [Derek Yu 1]
- Even dimensions help isometric work. [Slynyrd Pixelblog 41](https://www.slynyrd.com/blog/2022/11/28/pixelblog-41-isometric-pixel-art)
- Otherwise: 16px for tiny readable icons and tiles, 32px for characters with visible faces and
  gear, 48px and up when the engine or detail demands it (judgment).
- Keep pixel density identical across sprites, tiles, and UI in one project; never mix scales
  (judgment).
