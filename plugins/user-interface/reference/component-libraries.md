# Component libraries

How to choose a library for an interface component (a dialog, popover, menu, select, toast,
command menu, date picker, data table, drag and drop, a virtualized list) instead of hand-rolling
it. The criteria decide; the primitives table below names a default for React only, because which
libraries fit depends on the project's stack and changes faster than this file. For any other
stack, look up its current options from its own ecosystem and official sources at the time of the
choice. The project's design system and conventions override everything here.

## Why not hand-roll

A hand-built dialog, menu or select usually misses focus management, keyboard behavior, dismissal
rules and screen-reader semantics. Reach for a library first for any component with those
behaviors; build it only when the project's own components already cover it or no library fits.

Pick the component for what it must hold. Interactive content goes in a click-triggered popover,
never a hover tooltip: a "Learn more" link inside a hover tooltip is unreachable.

- **Pointer**: WAI-ARIA Authoring Practices Guide, tooltip pattern,
  <https://www.w3.org/WAI/ARIA/apg/patterns/tooltip/#aboutthispattern>
- **As of**: 2026-10-29
- **Recheck trigger**: the tooltip pattern leaves work-in-progress status or revises what a tooltip
  may contain.

## Prefer what is already there

1. Read the project's manifests, component folders and stories for a component library or
   primitives already in use, and the design system's own components. Use them.
2. When the project already uses a library for the task, keep it even if another would be the pick
   for a new project. Mention a better fit if there is one; never replace an installed dependency
   unasked.
3. Add a new dependency only for a task nothing installed covers, and ask before adding it.

## Criteria for a new choice

- **Headless or styled.** A project with its own design system wants unstyled, accessible
  primitives it can style; a project without one may want a styled library whose look it accepts.
  A styled library's look must not fight the project's design language.
- **Accessibility.** Keyboard support, focus handling and semantics that follow the WAI-ARIA
  Authoring Practices pattern for the component, documented by the library.
- **Fit with the stack.** Built for the project's framework and rendering model (server rendering,
  islands, native), styling approach and browser or platform targets, with no second framework
  pulled in.
- **Maintenance.** Recent releases, responsive issue handling, more than one maintainer or a
  backing organization, and a stated support policy.
- **License.** Compatible with the project's license and distribution.
- **Weight.** The cost the component adds, measured against what it replaces; one component should
  not pull in a whole suite.
- **Escape hatches.** Control over rendering and state where the design needs it (for example a
  custom trigger or a controlled open state).

- **Pointer**: WAI-ARIA Authoring Practices Guide, patterns,
  <https://www.w3.org/WAI/ARIA/apg/patterns/>
- **As of**: 2026-10-11
- **Recheck trigger**: the guide publishes a new pattern or revises one the component uses.

## Accessible primitives for React

When a React project has no primitives library installed and its design system names none, use
the `components.primitives_default` setting for accessible component primitives: the resolved
`config.values.components.primitives_default` that `/user-interface:design` detects, else the value
in `defaults.yaml`. It names a primitives library below by its setting value; shadcn/ui is not a value,
because it builds on one of them. If it doesn't fit the codebase, use whatever
does, but the accessibility bar (focus management, ARIA, keyboard support) is non-negotiable.

| Setting value | Library | Install | Composition |
|---|---|---|---|
| `base-ui` | Base UI | <https://base-ui.com/react/overview/quick-start#install-the-library> | <https://base-ui.com/react/handbook/composition#changing-the-default-rendered-element> |
| `radix` | Radix Primitives | <https://www.radix-ui.com/primitives/docs/overview/getting-started#1-install-the-primitive> | <https://www.radix-ui.com/primitives/docs/guides/composition#changing-the-element-type> |
| `react-aria` | React Aria | <https://react-aria.adobe.com/getting-started#install> | <https://react-aria.adobe.com/customization#dom-elements> |
| none (builds on a row above) | shadcn/ui | <https://ui.shadcn.com/docs/installation#use-the-cli> | the composition page of the library it builds on |

A setting value is a key, not a package name: install a library by the package name its Install
page gives, never by the setting value or a name recalled from memory. Treat shadcn/ui components
copied into the project as the project's own, and the library they build on as installed. Before
relying on a library for the accessibility bar, read what its accessibility page leaves to the
project.

- **Pointer**: the pages in each row's Install and Composition columns; Base UI's accessibility
  page, <https://base-ui.com/react/overview/accessibility#focus-management>; which libraries
  shadcn/ui builds on, <https://ui.shadcn.com/docs/changelog/2026-07-base-ui-default#whats-changed>
- **As of**: 2026-10-29
- **Recheck trigger**: a library moves its install or composition section, changes its package
  name, or shadcn/ui changes the libraries it builds on.

## Report the choice

Name the task, the one library chosen (or the installed one kept), why it fits on the criteria
above, and where its current documentation lives. When nothing fits, say so and name what the
project would have to build. Motion for the component follows `animation/behaviors.md`; the API of
a shared component built on the primitives follows `types/web/component-api.md`.
