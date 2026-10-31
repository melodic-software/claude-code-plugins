# Interface states

Read this when a web screen shows data that can be missing, slow or failing, or a control that
reports back to the person using it: an empty list, a loading view, a failed request, an optimistic
update, a copy button, a toast, a badge or a tag. The project's own state components (an
`EmptyState`, a skeleton, a toast library) and its copy conventions win over every rule here;
suggest a change to them, never override them.

The examples are React (JSX) and CSS. In another framework, keep the behavior and write it in that
framework's own idiom.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

Other concerns own the neighbors, one home each: whether a submit button is disabled while its
request is in flight, a failed form submit, a label that toggles its control, a field error shown
inline next to its field
and error copy that names the fix are the `forms` concern; a disabled control's muted color token
is the `color` concern; a value that flashes, a label whose width changes after first paint and a
skeleton whose box differs from the loaded content are the `layout-stability` concern; announcing
an async change to a screen reader, an error not signaled by color alone and a toast's timing for
people who need longer are the `accessibility` concern; how a toast or skeleton moves is the
`motion` concern; debouncing a search request is the `web-performance` concern.

Contents: 1 every view has four states, 2 empty states, 3 failed requests, 4 wait indicators, 5
loading states hold the page's shape, 6 optimistic updates, 7 copy actions confirm, 8 feedback while
the user acts, 9 toast duration, 10 badges and tags.

## 1. Every view has four states

Every data-driven view has four states (loading, empty, error, full) and the person who built it
only ever saw the last one. A new user sees the other three first.

For each data-driven view, find the four branches in the code. A branch that doesn't exist is the
finding.

The list of states every control and view designs is in the `web-layout` concern's principles;
this file holds the detail for each data state and the feedback states below.

**Audit: Important.** A data view whose loading, error or empty state renders the same as another of
its four (an error or a loading view that shows the empty state). A missing branch is graded in its
own section below.

**Audit: Important.** A control whose hover or disabled state is missing or looks the same as its
default, a submit button's disabled look included. A button's missing `:active`, whether a submit
button is disabled while its request is in flight, and a form field's hover, focus and error states
are the `forms` concern's; a removed focus ring is the `accessibility` floor.

## 2. Empty states exist and teach

An empty list is a first-run screen, not an error. A view that renders `null`, a bare table header,
or "No items" when there's no data is the first thing every new account sees.

**Hunt for:** `.map()` with no `length === 0` branch; `return null` on empty data; copy like "No
items", "No data", "Nothing here", "No results found." with nothing after it.

Show what belongs there and the action that creates it. The shape: a short headline, one line of
explanation, and the primary action that creates the first item.

```jsx
if (projects.length === 0) {
  return (
    <EmptyState
      title="No projects yet"
      description="Projects hold your team's work. Create one to get started."
      action={<Button onClick={createProject}>Create project</Button>}
    />
  );
}
```

Size the empty state to the dimensions of the filled state, so completing the action doesn't shift
the layout. A search or filter that returns nothing is a different empty state: say what was
searched and offer to clear it.

The branch is a fix. The words are content: if the project has no empty-state copy to follow, write
the branch with the closest existing pattern and flag the copy for the human list.

The human list is the part of your reply or report that names what a person must supply because
the code cannot: here, the empty-state copy. Write draft copy in the branch and mark it there as a
draft for that person to replace.

**Audit: Blocking.** A first-run screen (the first view a new account lands on) with no empty
branch, or one that renders `null`, a bare header or "No items" with no action.

**Audit: Important.** The same on any other view, or a search or filter with no results that
neither says what was searched nor offers to clear it.

**Audit: Important.** An empty state sized differently from the filled state, so completing its
action shifts the layout.

## 3. Failed requests render something useful

The network will fail on launch day. A view that renders nothing, spins forever, or crashes to a
white screen when its request fails is broken for everyone on a train.

**Hunt for:** data hooks whose `error` / `isError` is never read; `fetch` with no `.ok` check;
routes with no `error.tsx` / error boundary / `errorElement`; no `not-found` page; "Something went
wrong" with no next step.

An error state says what happened and offers a specific recovery: a retry button that refetches, a
link back to somewhere that works. "Something went wrong" plus a back button ends the journey. The
framework's default error and 404 pages are findings; they're unstyled, off-brand, and in
production they say nothing.

Write the message in product terms. Never render the raw exception message, response body or stack
trace: it shows internals to whoever sees the screen. Log the detail, and where support needs it,
show an id the person can quote.

The hunt's file and prop names are search tokens for Next.js and React Router; in another router,
hunt for its own error-route and not-found conventions. A failed form submit is the `forms` concern.

This section grades the failed view: the screen or panel the error replaced. The same generic
string in a toast, a dialog or an inline message is graded once, as copy, under "Plain-language
copy" in `../../principles.md`.

- **Pointer**: Next.js, Error Handling, "Nested error boundaries" and "Not found" (the `error` and
  `not-found` file conventions),
  <https://nextjs.org/docs/app/getting-started/error-handling#nested-error-boundaries> and
  <https://nextjs.org/docs/app/getting-started/error-handling#not-found>; React Router, `<Route>`
  props `ErrorBoundary` and `errorElement` (the two are mutually exclusive),
  <https://reactrouter.com/api/components/Route#errorboundary>
- **As of**: 2026-10-29
- **Recheck trigger**: Next.js renames the `error` or `not-found` file convention, or React Router
  drops `errorElement` or `ErrorBoundary` from the route props.

**Audit: Blocking.** A view that renders nothing, spins forever or crashes to a white screen when
its request fails; a route that no error boundary covers, its own or one above it; a failed view
that says "Something went wrong" with no next step; or the framework's default error or 404 page
left in production.

**Audit: Important.** An error state that renders a raw exception message, response body or stack
trace.

## 4. Every wait over 400ms has an indicator

Silence past 400ms reads as broken. The user clicks again or leaves. Keeping that second click from
firing the request twice is the `forms` concern.

**Hunt for:** data hooks whose `isLoading` / `isPending` is never read; route segments with no
`loading.tsx` or `<Suspense fallback>`; buttons that start async work with no pending state;
`fallback={null}`.

The opposite is also a finding: a spinner that flashes for 80ms on a fast response. Delay the
indicator ~150ms so fast responses never show it.

- **Pointer**: Next.js, `loading.js` file convention, "Instant Loading States",
  <https://nextjs.org/docs/app/api-reference/file-conventions/loading#instant-loading-states>;
  React, `<Suspense>`, "Props" (`fallback`), <https://react.dev/reference/react/Suspense#props>
- **As of**: 2026-10-29
- **Recheck trigger**: Next.js renames the `loading` file convention, or React renames the
  `fallback` prop of `<Suspense>`.

**Audit: Important.** A wait over 400ms with no indicator, or an indicator that flashes on a fast
response because nothing delays it.

## 5. Loading states hold the page's shape

A spinner collapses the page to nothing, then the content arrives and everything jumps. A skeleton
occupies the same box the loaded content will, so nothing moves when the data lands.

**Hunt for:** a centered spinner as the loading state of a list, table, card grid, or page;
`dynamic()` / `lazy()` imports with no sized fallback.

Spinners are right for an action inside a control (a submitting button). Skeletons are right for
content.

This section chooses between a skeleton and a spinner. How big the skeleton is, its height and row
count against the loaded content, is the `layout-stability` concern.

`dynamic()` and `lazy()` are search tokens for Next.js and React; give the fallback wherever the
framework takes a lazy import's loading UI.

- **Pointer**: Next.js, Lazy Loading guide, "Adding a custom loading component" (the `loading`
  option of `next/dynamic`),
  <https://nextjs.org/docs/app/guides/lazy-loading#adding-a-custom-loading-component>; React,
  `lazy`, "Lazy-loading components with Suspense" (the fallback comes from a `<Suspense>` boundary
  above the lazy component), <https://react.dev/reference/react/lazy#suspense-for-code-splitting>
- **As of**: 2026-10-29
- **Recheck trigger**: Next.js renames `next/dynamic` or its `loading` option, or React changes
  where a `lazy` component's fallback comes from.

**Audit: Important.** A centered spinner as the loading state of a list, table, card grid or page.

## 6. Optimistic updates revert on failure

Prefer optimistic updates that revert on error over waiting for the server before updating the UI.
Optimistic feels instant.

An optimistic update that never reverts shows the user a lie: the item looks saved, the toggle looks
on, and the server never heard about it.

**Hunt for:** state set before an `await` with no `catch` restoring the previous value; `onMutate`
with no `onError` rollback (React Query); `useOptimistic` with no error surface.

Fix: on failure, restore the previous value and say so ("Couldn't update. Try again.").

Roll back through the library's own mechanism, which the pointer names. Where the library restores
the previous value by itself, the fix still adds the message.

- **Pointer**: TanStack Query, Optimistic Updates, "Via the cache" (what `onMutate` returns is
  passed to `onError`, which rolls back with it),
  <https://tanstack.com/query/latest/docs/framework/react/guides/optimistic-updates#via-the-cache>;
  React, `useOptimistic`, "How optimistic state works" (a failed Action leaves the real value
  unchanged when it is set only on success, so the screen shows what it showed before),
  <https://react.dev/reference/react/useOptimistic#how-optimistic-state-works>
- **As of**: 2026-10-29
- **Recheck trigger**: TanStack Query changes what `onMutate` passes to `onError`, or React changes
  what `useOptimistic` renders after a failed action.

**Audit: Important.** An optimistic update with no rollback on failure, or a failure that rolls back
without telling the user.

## 7. Copy actions confirm

Copy-to-clipboard buttons must confirm: swap to a checkmark for ~1.5s. Without feedback, users
click three more times to check it worked.

**Audit: Suggestion.** A copy-to-clipboard button with no confirmation.

## 8. Feedback while the user acts

Hover states should confirm affordance, not just decorate: pair the color change with a cursor
change and a subtle underline where appropriate.

The cursor and underline matter most on a control nothing else marks as interactive, such as a
text link or a clickable row.

Trigger actions on `click`, or the form's submit handler, not `mousedown` or `mouseup`. Mousedown
fires before the user commits, so they lose the ability to cancel by dragging away. Mouseup never
fires for keyboard or assistive-technology activation; `click` does, and it waits for the release.

Press feedback can still start on press: the feedback shows the press, and the action waits for the
release. The rule covers an action the click commits (a submit, a delete, a navigation); opening a
menu or a select, or starting a drag, on press commits nothing.

Auto-advancing inputs (verification codes) feel clever until someone needs to correct a digit.
Waiting for tab is safer.

Sliders update their value live during drag. On-release-only feels disconnected and makes precise
values hard to hit.

**Audit: Important.** An action that commits on `mousedown` or `pointerdown`, so dragging away
cannot cancel it. A menu, a select or a drag that starts on press is not this finding.

**Audit: Suggestion.** A hover state that changes only color on a control nothing else marks as
interactive; a code input that moves focus on its own; a slider that updates only on release.

## 9. Toast duration scales with content

Toast duration scales with content: compute it from word count (~200–250 wpm reading speed) instead
of a flat 2s for every message.

**Audit: Suggestion.** One flat duration for every toast, whatever its length.

## 10. Badges count, tags categorize

Badge vs tag semantics: a badge implies a count, a tag implies a category. A "New" feature marker is
neither: it needs its own treatment.

**Audit: Suggestion.** A badge used for a category, a tag used for a count, or a "New" marker styled
as either.
