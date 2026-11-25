# Let a consumer brand rendered pages through one shared token layer

- Status: accepted
- Date: 2026-11-25
- Related: [#16412](https://github.com/melodic-software/claude-code-plugins/issues/16412) (the
  issue, its refinement questions Q1 to Q5, and the owner's decisions of 2026-11-17 and
  2026-11-24); [rendered-views](../contracts/rendered-views/README.md#the-shared-chrome-reference)
  (the contract this record amends);
  [ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)
  (generated shared copies); [ADR 0064](0064-home-plugin-customization-in-docs-conventions-yaml.md)
  and [ADR 0075](0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)
  (the convention home and the layer order)

## Context

The rendered-views contract gives every page family one chrome: the system, light and dark toggle,
the comment box and the accessibility floor, and it said "A page offers no other theme choice: no
team or user theme override, no accent or palette picker"
(`docs/contracts/rendered-views/README.md:865-868` before this change). The chrome's canonical copy
is `lib/html-chrome.html`, generated into four plugins (`scripts/shared-copies.txt:644-647`:
visualization, adhd, planning, architecture). Its palette, type stacks and per-scheme roles are
literal values in one `:root` block (`lib/html-chrome.html:37-62`), flipped for dark by
`prefers-color-scheme` and by `data-theme` (`lib/html-chrome.html:64-84`).

Most page sources do not take those values from the chrome. Each carries its own palette, so a
consumer who wants their company or product branding on every page has nothing to set, and the
marketplace has no single place to improve its own default look. The planning interview page reads
a `themeTokens` setting from three layers and then applies none of it
(`plugins/planning/surface/README.md:146,150`), a branding key that already exists and does nothing.

The owner decided the design questions on the issue: Q1 on 2026-11-17, and Q2 to Q5 on 2026-11-24,
each accepting the refinement's recommendation. This record writes those decisions down and settles
the parts the evidence decides.

## Decision

1. **A consumer may override palette, type and logo, and nothing else** (Q1). Layout, the
   accessibility floor, the theme toggle and the comment box stay fixed. The override is
   configuration read when a page is built, never a control on the page: a page still offers no
   accent or palette picker, and the system, light and dark toggle stays its only theme control.
2. **What each override covers.**
   - **Palette**: values for the chrome's named roles (`bg`, `fg`, `panel`, `muted`,
     `accent`, `link`, `focus`), set per scheme (`light`, `dark`). A role or scheme left unset keeps
     the shipped value. Basis: the roles the chrome already flips per scheme,
     `lib/html-chrome.html:56-84`; `accent` names the role `--clay` plays today
     (`lib/html-chrome.html:178`).
   - **Type**: the three stacks the chrome defines, `serif`, `sans` and `mono`
     (`lib/html-chrome.html:48-50`), as installed font families or brand font files embedded in the
     page as `data:` URLs in `@font-face`. A page never loads a font from a URL, so it stays one
     self-contained file that works offline (`lib/html-chrome.html:131`).
   - **Logo**: either one inline SVG, which must pass the builder's SVG allowlist
     (`docs/contracts/rendered-views/README.md:232-243`, which refuses `<image>`, `<use>`, `<script>`
     and SVG `<style>`), or one PNG or JPEG embedded as a `data:` URL, plus a text label, shown in a
     fixed slot of the chrome's bar. A logo is never loaded from a URL.
   - **Policy change (owner decision on #16412, 2026-11-25).** Today the page policy is
     `default-src 'none'` and the report profile bans `url(` inside `<style>` and every URL-bearing
     attribute (`docs/contracts/rendered-views/README.md:152-155`, `:179-181`), which blocks both
     embedded forms. The first work item widens exactly this much: the policy gains `img-src data:`
     and `font-src data:`, and the validator admits a `data:` URL with an `image/png`,
     `image/jpeg` or font media type only in the logo slot and in `@font-face`. Every other
     scheme and position stays refused. The owner accepted this recommendation in session:
     "go w/ recommendations".
3. **The accessibility floor decides, not the override.** The resolver checks each resolved pair the
   floor names (body text, link text, focus outline, in both schemes;
   `lib/html-chrome.html:176-180`) and drops an override that fails it, keeping the shipped value
   for that role and printing a notice that names the role, the scheme and the measured ratio.
   A page is never built below the floor.
4. **Values are validated, never escaped into place.** Override values land inside `<style>` and
   inline SVG, where the security baseline forbids unescaped interpolation
   (`docs/contracts/rendered-views/README.md:717-719`). The resolver accepts a color only as a
   six-digit hex value, a font family only from a closed character set, an SVG logo only after the
   SVG allowlist check, and an embedded logo or font file only as a file the resolver reads, checks
   by its magic bytes against the allowed media types, and base64-encodes itself. A value that fails is reported and ignored without dropping another layer's
   value, as `medium` is (`docs/contracts/rendered-views/README.md:908`).
5. **The setting lives in the convention home, with `userConfig` as the per-user value** (Q2). The
   key is `branding` in the rendered-views team file `docs/conventions/rendered-views.yaml` and its
   personal override `docs/conventions/rendered-views.local.yaml`, the scopes `medium` already uses
   (`docs/contracts/rendered-views/README.md:885-890`). Each view-lane plugin also takes a per-user
   value through its `userConfig`, as it does for `medium`. Precedence is plain ADR 0075 order,
   personal override, then team, then `userConfig`, then the shipped default, so the convention home
   wins on conflict. `branding` does not take the publish trust walk `medium` takes
   (`docs/contracts/rendered-views/README.md:893-906`): it changes how a page looks, never whether it
   leaves the machine. A lane that reads the team file from a named commit (`--team-ref`,
   `docs/contracts/rendered-views/README.md:910-912`) reads `branding` from that commit too. The one
   resolver, `lib/view-settings.mjs` (`docs/contracts/rendered-views/README.md:882`), resolves it.
6. **One token layer, copied per plugin** (Q3). The token layer is one canonical file,
   `lib/html-tokens.css`: the shipped values for every role and stack in both schemes, and the
   rules that apply them. `lib/html-chrome.html` takes its values from it instead of carrying its
   own. Each plugin that renders pages registers its own generated copy,
   `plugins/<plugin>/reference/html-tokens.css`, in `scripts/shared-copies.txt`, as `html-chrome.html`
   is registered (`scripts/shared-copies.txt:644-647`); `scripts/sync-shared-copies.sh` already
   generates CSS copies (`scripts/sync-shared-copies.sh:101-130`). A plugin never reads a sibling
   plugin's file. A page builder inlines its plugin's copy and the resolved overrides into the
   page's one `<style>` element, so the page stays one self-contained file and the policy's
   `style-src` hash covers the overrides (`docs/contracts/rendered-views/README.md:180`).
7. **Drift is caught by checks, not prose.**
   - **The copies match their canonical.** The token layer joins the existing shared-copies gate:
     `scripts/sync-shared-copies.sh --check`, run in CI by `pr-require-checks.yml:2909-2911`, fails
     a copy that differs from what `lib/html-tokens.css` generates, and `--check-bump`
     (`pr-require-checks.yml:2643`) fails a canonical change that does not bump each carrying
     plugin. Registering the copies is all it takes.
   - **A page takes its palette and stacks from the layer.** A new check fails a page source that
     defines a palette role or a type stack with a literal value outside the token layer. That
     check does not exist today and is its own work item.
8. **The migration order** (Q4).
   - **First: visualization, adhd, planning and architecture**, the plugins that carry the chrome.
     Q4's recommendation named three because three carried it when the refinement was written; the
     architecture plugin took a copy on 2026-11-16
     (`docs/contracts/rendered-views/CHANGELOG.md:17-20`, `scripts/shared-copies.txt:647`). Q4's
     reason, carrying the chrome, applies to it in the same way, so it migrates in the first wave.
   - **Then the rest, by the inventory**, page sources that already use the chrome's `--clay`
     before those with only their own scheme flip. Pages on the shared view builder
     (`scripts/shared-copies.txt:359-370,564-568`) come before self-styled pages, because the
     builder is one place to inline the layer.
   - **The shared interview surface migrates with planning; nothing stays apart.** Both interview
     pages already copy the chrome's toggle, comment box and rules
     (`plugins/planning/surface/README.md:150`), and no requirement of theirs differs from the
     other pages' on palette, type or logo. The planning slice retires `interview_page.themeTokens`
     and `theme.json` in favor of `branding`, so the marketplace keeps one branding key. A later
     slice that finds a page whose requirements differ records the page and the reason in the
     contract before keeping it apart.
9. **This issue records the design, the contract edit and the work items, and implements nothing**
   (Q5).

### The inventory

Command, run at the repository root on 2026-11-25:

```sh
grep -rlE --exclude-dir=node_modules -e '--clay|prefers-color-scheme' plugins
```

It matches 55 files. Files with `prefers-color-scheme` sit in 18 plugins and files with `--clay` in
9. Dropping the four generated chrome copies and the files that do not ship a page (evals, tests,
probes, Markdown, JSON and text fixtures) leaves 26 page sources in 15 plugins, the migration's
scope:

| Wave | Plugin | Page sources (`--clay` count, `prefers-color-scheme` count) |
|---|---|---|
| 1 | visualization | `reference/html-loop-closure.html` (9, 1) and pages the visualize skill builds on the chrome |
| 1 | adhd | none checked in: `/adhd:clarify` builds its page on the chrome copy |
| 1 | planning | three skill view templates, `surface/index.html`, `shared/web/app.js`, `proto.js`, `proto-pin.js` (0, 1 to 3 each) |
| 1 | architecture | `templates/map-view.html` (0, 1) and `scripts/deepening-report.mjs` |
| 2 | education, event-storming, harness-ops, knowledge, review | `quiz-me/scripts/build-report.mjs` (2, 1), `page-kit.mjs` and `illustrate/templates/explainer.html` (0, 1); `build-bc-view.mjs` (1, 1); `build-dashboard.mjs` (1, 1); `build-menu-view.mjs` (1, 1); `explain-change/templates/digest.html` (2, 1) |
| 3 | debugging, discovery, machine-health, work-items | one or two templates each on the shared view builder (0, 1) |
| 4 | formal-verification, playbooks, prototype | `chart/reference/render-theme.css`; `reference/repo-sweep-plan-page.html`; `notes-bridge/host.html`, `notes-bridge/proto-pin.js`, `explore-directions/assets/variant-switcher.html` (0, 1 to 3 each) |

The user-interface and playgrounds matches are guidance, evals and probes about theming, not pages,
so they are out of scope.

## Alternatives considered

- **(a) Palette only.** Leaves type and logo, the two most visible marks of a brand, fixed. Not
  chosen (Q1, option B).
- **(b) Layout as an override too.** A consumer layout could move or drop the toggle, the comment box
  or the floor's focus and contrast rules, which this design keeps fixed. Not chosen (Q1).
- **(c) User config as the primary home.** A team's branding would then need every member to set it.
  Not chosen (Q2).
- **(d) A dependency plugin or an import from a sibling plugin.** ADR 0019 rejects a dependency plugin
  and marketplace symlinks for shared code. Not chosen (Q3).
- **(e) Keep `interview_page.themeTokens` beside `branding`.** Two keys for one choice, one of them
  read and never applied. Not chosen.
- **(f) Keep the logo to inline SVG and type to installed fonts.** No policy change, but most brand
  kits ship a raster logo and a font file, so their branding would only half apply. Not chosen
  (owner, #16412, 2026-11-25).
- **(g) Load the logo and fonts from a URL.** Pages would make network requests, stop working
  offline and could be tracked when opened. Not chosen.

## Consequences

- The rendered-views contract allows the three overrides and states that the page still offers no
  picker. The `branding` key is added to the contract's settings section, the config-cascade
  registry row for `rendered-views`, and the schema in the first work item, when the resolver
  learns it.
- The chrome's header comment, which repeats the old "no team or user theme override" rule
  (`lib/html-chrome.html:15-17`), changes in the first work item, since editing it regenerates
  four plugins' copies.
- Plugins that render pages without `lib/view-settings.mjs` (event-storming, knowledge,
  formal-verification, playbooks, machine-health) register a copy of it in their migration slice.
- Every page built after its plugin migrates carries the consumer's branding with no change on the
  consumer's side beyond setting `branding` once.
