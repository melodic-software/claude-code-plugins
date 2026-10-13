# Component libraries

How to choose a library for an interface component (a dialog, popover, menu, select, toast,
command menu, date picker, data table, drag and drop, a virtualized list) instead of hand-rolling
it. It names criteria, not libraries: which libraries fit depends on the project's stack and
changes faster than this file, so look up the stack's current options from its own ecosystem and
official sources at the time of the choice. The project's design system and conventions override
everything here.

## Why not hand-roll

A hand-built dialog, menu or select usually misses focus management, keyboard behavior, dismissal
rules and screen-reader semantics. Reach for a library first for any component with those
behaviors; build it only when the project's own components already cover it or no library fits.

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

## Report the choice

Name the task, the one library chosen (or the installed one kept), why it fits on the criteria
above, and where its current documentation lives. When nothing fits, say so and name what the
project would have to build. Motion for the component follows `animation/behaviors.md`.
