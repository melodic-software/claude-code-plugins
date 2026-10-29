# Component API

Read this when a change introduces or reshapes a shared component's API: its props, its parts, its
state and how consumers customize it. A component used once inside one screen does not need it. The
project's own component conventions win over every rule here; suggest a change to them, never
override them.

A component API is a contract. Good ones make the common case a one-liner and the uncommon case
possible without forking. The failure modes are always the same: too rigid (users fork or hack
around you) or too configurable (30 props nobody can hold in their head). Reach for composition
before configuration, name things the way the platform names them, and support both controlled and
uncontrolled state when state is involved.

The examples are React (JSX). In another framework, keep the contract and write it in that
framework's own idiom. Working code for each pattern is in `component-api/implementation.md`; which
primitives library to build on is in `../../component-libraries.md`.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

## 1. Composition over configuration

Expose structure as JSX children, not configuration objects:

```jsx
// Good - composable
<Card>
  <CardHeader>
    <CardTitle>Title</CardTitle>
    <CardDescription>Description</CardDescription>
  </CardHeader>
  <CardContent>Content here</CardContent>
  <CardFooter>
    <Button>Action</Button>
  </CardFooter>
</Card>

// Bad - configuration object
<Card
  header={{ title: "Title", description: "Description" }}
  content="Content here"
  footer={{ actions: [{ label: "Action", onClick: () => {} }] }}
/>
```

Prop explosion is the same mistake one prop at a time: `leftIcon`, `rightIcon`, `iconSpacing`,
`iconSize`... just use children: `<Button><Icon /> Click <Arrow /></Button>`.

**Audit: Important.** Structure passed as configuration objects, or a wall of props where children
and compound parts would do.

## 2. Compound components for multi-part UI

When a component has multiple related parts sharing implicit state, split it into compound
components instead of prop-drilling everything through one root:

```jsx
// Good - compound components
<Dialog>
  <Dialog.Trigger>Open</Dialog.Trigger>
  <Dialog.Content>
    <Dialog.Title>Are you sure?</Dialog.Title>
    <Dialog.Description>This action cannot be undone.</Dialog.Description>
    <Dialog.Close>Cancel</Dialog.Close>
  </Dialog.Content>
</Dialog>

// Bad - prop drilling everything
<Dialog
  trigger="Open"
  title="Are you sure?"
  description="This action cannot be undone."
  closeText="Cancel"
/>
```

Use compound components when:

- Multiple related elements share implicit state
- The component has slots (header, body, footer)
- The order or presence of children varies between usages
- Consumers need flexible composition

Don't use them when:

- The component is simple with a fixed structure
- It has 1-3 props
- The structure never changes

Share the implicit state through React context: the root provides, the parts consume.
Implementation in `component-api/implementation.md`.

**Audit: Important.** A multi-part component that drills every part through props on one root
instead of compound parts sharing context.

## 3. The Goldilocks level of customization

Too little customization and users fork your component or add hacky workarounds. Too much and the
API becomes confusing and a maintenance nightmare. Aim for the middle:

```jsx
// Too rigid - no customization
<Button>Click me</Button>

// Too flexible - overwhelming API
<Button
  backgroundColor="#000"
  hoverBackgroundColor="#333"
  activeBackgroundColor="#111"
  borderRadius={4}
  paddingX={16}
  paddingY={8}
  fontSize={14}
  fontWeight={500}
  // ... 30 more props
>
  Click me
</Button>

// Just right - variants + escape hatch
<Button variant="primary" size="md" className="custom-override">
  Click me
</Button>
```

Layer customization in this order:

1. **Variants**: predefined options (`primary`, `secondary`, `danger`)
2. **Size**: predefined sizes (`sm`, `md`, `lg`)
3. **className**: escape hatch for one-off overrides
4. **asChild**: render as a different element (section 7)

Boolean soup instead of variants is the common way to get this wrong. `<Button primary large
rounded>` invites invalid combinations. Use `<Button variant="primary" size="lg" radius="full">`.

When implementing variants, express the styles in the project's existing styling system (Tailwind,
CSS Modules, vanilla-extract, styled-components: whatever the codebase already uses). Don't impose a
new one.

**Audit: Important.** Style props in place of variants and sizes, boolean props that combine into
invalid states, or variant styles written in a styling system the project does not use.

### Finite choices

The most important thing with components for agents is to have a finite number of choices. Even
better, the fewer choices you expose, the less room there is for the agent to improvise, which is
the same reason design systems work for large human teams.

Types make this enforceable. If `variant` is a union of `"primary" | "secondary" | "danger"`, an
invented variant would result in a build error which is easy to catch by an agent.

Agents often invent `ghost` and `destructive` variants because every codebase they were trained on
had them. Tell the model which variants exist, and that it must not use ones that don't.

A component is one agents write against when the project's agent instructions or design-system
guidelines name it as a component to build with. For those, leave out the `className` escape hatch
in the layers above; keep it for components only people compose. Avoid escape hatches where you
can. If every component accepts an arbitrary `className`, there's a chance for the agent to use it
to "fix" spacing and colors. Try to reduce the margin for error as much as possible. You can even
go further and disallow the use of HTML elements and enforce the use of your components
exclusively.

- **Pointer**: Figma, design-system guidelines for Make kits, the example `button.md`,
  <https://help.figma.com/hc/en-us/articles/43602393097239-Write-design-system-guidelines-for-Make-kits#h_01S60MHT1T2MH1K3JKFQJCMAK8>
- **Correlate with**: Polar's post on its LLM-safe design system,
  <https://polar.sh/blog/orbit-llm-safe-design-system>
- **As of**: 2026-10-29
- **Recheck trigger**: the Figma article moves, or revises its component guidelines on variants or
  raw HTML elements.

**Audit: Important.** A variant or size prop typed as an open `string` where a union of the
existing values would make an invented one fail the build, or a call site using a variant the
component does not define.

## 4. Name props like the platform does

Be consistent across every component, mirror HTML where possible:

```jsx
// Good - consistent patterns
<Input disabled />
<Button disabled />
<Select disabled />

// Bad - inconsistent
<Input disabled />
<Button isDisabled />
<Select readonly />
```

Boolean props get positive names, never double negatives:

```jsx
// Good
<Input disabled />
<Modal open />

// Bad
<Input notEnabled />
<Modal isNotClosed />
```

Event handlers are prefixed with `on`:

```jsx
// Good
<Input onChange={handleChange} onBlur={handleBlur} />
<Dialog onOpenChange={setOpen} onClose={handleClose} />

// Bad
<Input handleChange={handleChange} blurHandler={handleBlur} />
```

Props are named for intent, and the common case is a one-liner.

**Audit: Suggestion.** A prop name that differs from the HTML attribute or from the same prop on a
sibling component, a negative boolean, or an event handler without the `on` prefix.

## 5. Support both controlled and uncontrolled state

Any stateful component should work both ways: internal state by default, external state when the
consumer needs it:

```jsx
// Uncontrolled
<Input defaultValue="hello" />

// Controlled
<Input value={value} onChange={(e) => setValue(e.target.value)} />
```

Full dual-mode implementation in `component-api/implementation.md`.

**Audit: Important.** A component that holds state and accepts only `value` and `onChange`, or only
`defaultValue`.

## 6. Play nice with the DOM

- **Forward refs** on every component that wraps a DOM element: otherwise focus management,
  tooltips, and popover positioning break for composers. How depends on the React version
  (`component-api/implementation.md`, "Forwarding refs").
- **Spread remaining props** (`{...props}`) so `aria-*`, `data-testid`, and other HTML attributes
  pass through.
- **Pick defaults that work for 80% of usages**: e.g. `variant = "primary"`, `size = "md"`, and
  `type = "button"` (not `"submit"`: the safer default).

Code for all three in `component-api/implementation.md`.

Swallowing props is the usual failure: destructuring everything and forgetting `{...props}` breaks
`aria-*`, `data-*`, and testing attributes. Missing ref forwarding breaks focus management,
tooltips, and popover positioning for anyone composing your component.

**Audit: Blocking.** A component wrapping a DOM element that does not pass the ref through, or that
drops the remaining props, so `aria-*` attributes never reach the element.

**Audit: Important.** A button component whose `type` defaults to `"submit"` or is left to the
browser's default.

## 7. The `asChild` pattern

Let consumers swap the rendered element while keeping the behavior and styles:

```jsx
// Render as button (default)
<Button>Click me</Button>

// Render as link
<Button asChild>
  <a href="/page">Click me</a>
</Button>

// Render as Next.js Link
<Button asChild>
  <Link href="/page">Click me</Link>
</Button>
```

On a component built on a primitives library, use that library's own form of the pattern rather
than a second one beside it, and make the element passed in meet what its composition page asks of
a custom component. Each library's composition page is in the Composition column of the primitives
table in `../../component-libraries.md`, with its pointer record.

**Audit: Suggestion.** A shared component with no way to render a different element, so a link
styled as a button has to be a `<button>` that navigates.

**Audit: Important.** A component built on a primitives library that adds its own
element-swapping prop beside the library's.

## 8. Children for simple content, render props for data

```jsx
// Simple - use children
<Card>
  <CardContent />
</Card>

// Complex with data - render prop
<List
  items={users}
  renderItem={(user) => <UserCard user={user} />}
/>
```

For optional sections that take arbitrary JSX, use slot props (`header={<h2>Title</h2>}`): see the
slot pattern in `component-api/implementation.md`.

**Audit: Suggestion.** Data-driven content forced through children where a render prop would
pass the item, or a fixed optional section that takes only a string where a slot prop would take
JSX.

## 9. Hard to misuse

The component is hard to misuse: no required props that are easy to forget, no footguns.

**Audit: Important.** A required prop whose omission still renders (and so goes unnoticed), or a
prop combination the component accepts but cannot honor.

## 10. Extract a shared component late

Premature abstraction: don't create a shared component until you've copy-pasted the code 2-3
times. Wait for the pattern to emerge, then extract it.

**Audit: Suggestion.** A new shared component with a single call site.

## 11. Error boundaries

Wrap complex components in error boundaries so one broken widget doesn't take down the page. Code
in `component-api/implementation.md`.

**Audit: Important.** A complex widget whose render error can take down the whole page because no
error boundary wraps it.
