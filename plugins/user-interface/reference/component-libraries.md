# Component libraries

How to choose a library for an interface component (a dialog, popover, menu, select, toast,
command menu, date picker, data table, drag and drop, a virtualized list) instead of hand-rolling
it. The criteria decide, and this file names no library, because which libraries fit depends on the
project's stack and changes faster than this file. Look up the stack's current options from its own
ecosystem and official sources at the time of the choice. The project's design system and
conventions override everything here.

## Why not hand-roll

A hand-built dialog, menu or select usually misses focus management, keyboard behavior, dismissal
rules and screen-reader semantics. Reach for a library first for any component with those
behaviors; build it only when the project's own components already cover it or no library fits.

Pick the component for what it must hold. A tooltip holds a short text label and nothing a user
acts on; anything with a link, a button or a field goes in a click-triggered popover, so a keyboard
or touch user can reach it.

- **Pointer**: when deciding whether content fits a tooltip, fetch the WAI-ARIA Authoring
  Practices Guide tooltip pattern,
  <https://www.w3.org/WAI/ARIA/apg/patterns/tooltip/#aboutthispattern>, live.

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

## A new primitives library

When the project has no primitives library installed and its design system names none, the choice
is the project's: offer the candidates the criteria above leave, each with its current
documentation, and ask before adding one. Whichever library is chosen, the accessibility bar (focus
management, ARIA, keyboard support) is non-negotiable. Install a library by the package name its
own install page gives, never by a name recalled from memory. Treat components copied into the
project from a generator as the project's own, and the library they build on as installed. Before
relying on a library for the accessibility bar, read what its accessibility page leaves to the
project.

## Report the choice

Name the task, the one library chosen (or the installed one kept), why it fits on the criteria
above, and where its current documentation lives. When nothing fits, say so and name what the
project would have to build. Motion for the component follows `animation/behaviors.md`; the API of
a shared component built on the primitives follows `types/web/component-api.md`.
