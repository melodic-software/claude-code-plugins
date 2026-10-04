# Web: pages, web apps, components

`principles.md` applies first. On the web the project almost always has a look already, so most of
the work is reading it and routing to the tools that extend it.

## Read the project first

- Tokens: the token files and theme objects detect reports, then CSS custom properties and the
  Tailwind or CSS-in-JS theme config.
- Components: the component library in `package.json`, a `components.json` (shadcn), and Storybook
  stories. Reuse an existing component before writing a new one.
- Conventions: a design-system doc, the existing screens closest to the one being designed.

Name what you found before designing, so the user can correct it.

## Route

Take the concern (visual direction, typography and color, motion, components, design system,
accessibility, mockups, responsive testing, writing) to the highest-ranked route that is installed
and reachable. Where the project defines the concern, a style-imposing tool such as frontend-design
is not used for it; offer one only for a concern the project leaves open.

## When nothing covers the concern

- Layout: content first, one primary action per view, a consistent spacing scale.
- Type: the project's fonts; otherwise the platform's system font stack, a small modular scale, line
  length near 60-75 characters for body text.
- States: design loading, empty, error and success for every view that fetches data.
- Responsive: start narrow, add columns as width allows, test at phone and desktop widths.
- Accessibility: the floor in `principles.md`, with WCAG contrast measured, labels on every input,
  and focus visible.

## Platform design languages

When the project builds on Material Design or Fluent, follow its official guidelines and the
library's own components; do not restyle them toward another look.

- **Pointer**: Material 3, <https://m3.material.io/>; Fluent 2, <https://fluent2.microsoft.design/>
- **As of**: 2026-10-04
- **Recheck trigger**: either site publishes a new major version of its design language.
