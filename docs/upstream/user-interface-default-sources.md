# Independent sources for user-interface defaults

The `user-interface` plugin's defaults in
[`reference/defaults.yaml`](../../plugins/user-interface/reference/defaults.yaml) take their
number, in order, from the course record ([`aiforui-course.md`](aiforui-course.md)), then Emil
Kowalski's latest source ([`emilkowalski-skills.md`](emilkowalski-skills.md)), then the
independent sources below. A key with none of these is labeled heuristic in the defaults file's
comments. This page names, per key, the independent sources its default rests on; each source is
read live, and the value lives only in `defaults.yaml`. A team changes any of these keys through
its config, and a project's own tokens beat them.

| Key | Sources |
|---|---|
| `css.border_px.strong` | [Radix Themes tab list](https://github.com/radix-ui/themes/blob/main/packages/radix-ui-themes/src/components/_internal/base-tab-list.css), [Material Web navigation tab tokens](https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-primary-navigation-tab.scss), [Primer border size tokens](https://github.com/primer/primitives/blob/main/src/tokens/functional/size/border.json5) |
| `css.edge_fade.length`, `css.edge_fade.stops_percent` | [good-css `PRACTICES.md` at its audited pin](https://github.com/vojtaholik/good-css/blob/92d436ba1937d1b1407c47e35abb3e199eaace2e/PRACTICES.md) (record: [`good-css.md`](good-css.md)) |
| `css.focus_ring.width`, its text-relative term (the px term is in the course record) | [good-css `PRACTICES.md` at its audited pin](https://github.com/vojtaholik/good-css/blob/92d436ba1937d1b1407c47e35abb3e199eaace2e/PRACTICES.md), [Modern CSS: practical uses of CSS math functions](https://moderncss.dev/practical-uses-of-css-math-functions-calc-clamp-min-max/) |
| `icon.size_em` | [Phosphor icon context](https://github.com/phosphor-icons/react/blob/master/src/lib/context.ts), [react-icons icon base](https://github.com/react-icons/react-icons/blob/master/packages/react-icons/src/iconBase.tsx) |
| `spacing.s`, `spacing.m` | [Tailwind CSS v4.3.5 theme](https://github.com/tailwindlabs/tailwindcss/blob/v4.3.5/packages/tailwindcss/theme.css), [Radix Themes 3.3.0 space tokens](https://github.com/radix-ui/themes/blob/3.3.0/packages/radix-ui-themes/src/styles/tokens/space.css), [Bootstrap v5.3.8 variables](https://github.com/twbs/bootstrap/blob/v5.3.8/scss/_variables.scss) |
| `spacing.l` | the Tailwind and Radix files above, [Polaris size tokens](https://github.com/Shopify/polaris/blob/main/polaris-tokens/src/size.ts) |
| `layout.terminal_min_columns` | [Python `shutil.get_terminal_size`](https://docs.python.org/3/library/shutil.html#shutil.get_terminal_size), [GNU Coreutils general output formatting](https://www.gnu.org/software/coreutils/manual/html_node/General-output-formatting.html) |

- **Pointer**: when re-checking a key's default, fetch the sources in its row live and compare
  them with the key's value in `defaults.yaml`.
- **As of**: 2026-11-09
- **Recheck trigger**: a new release tag of Tailwind CSS, Radix Themes or Bootstrap past the one
  linked, a commit to a linked file on its default branch, a revision of the linked article, or a
  new Python or GNU Coreutils release that changes the linked section. A changed source moves the
  key's default, its copies and this row together, and the change is listed for the owner.
