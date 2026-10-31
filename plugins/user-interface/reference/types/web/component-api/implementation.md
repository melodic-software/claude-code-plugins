# Component API: implementation patterns

Working code for the patterns described in `../component-api.md`, in React. The project's own
helpers, file layout and export conventions replace the ones shown here.

## Compound components with context

Share implicit state through React context, not props: the root provides, the parts consume:

```jsx
const DialogContext = createContext(null);

function useDialogContext() {
  const context = useContext(DialogContext);
  if (context === null) {
    throw new Error("Dialog parts must be rendered inside <Dialog>.");
  }
  return context;
}

function Dialog({ open: controlledOpen, defaultOpen = false, onOpenChange, children }) {
  const [internalOpen, setInternalOpen] = useState(defaultOpen);
  const isControlled = controlledOpen !== undefined;
  const open = isControlled ? controlledOpen : internalOpen;

  function setOpen(next) {
    if (!isControlled) {
      setInternalOpen(next);
    }
    onOpenChange?.(next);
  }

  return (
    <DialogContext.Provider value={{ open, setOpen }}>
      {children}
    </DialogContext.Provider>
  );
}

function DialogTrigger({ onClick, ...props }) {
  const { setOpen } = useDialogContext();
  return (
    <button
      type="button"
      {...props}
      onClick={(e) => {
        onClick?.(e);
        setOpen(true);
      }}
    />
  );
}
```

The root takes `open`, `defaultOpen` and `onOpenChange`, so it works controlled and uncontrolled
like any other stateful component. A part rendered outside the root fails loudly instead of reading
a missing context, and the trigger runs the consumer's `onClick` before its own.

## Controlled + uncontrolled in one component

Internal state by default, external state when the consumer provides `value`:

```jsx
function Input({
  value: controlledValue,
  defaultValue,
  onChange,
  ...props
}) {
  const [internalValue, setInternalValue] = useState(defaultValue ?? "");

  const isControlled = controlledValue !== undefined;
  const value = isControlled ? controlledValue : internalValue;

  function handleChange(e) {
    if (!isControlled) {
      setInternalValue(e.target.value);
    }
    onChange?.(e);
  }

  return <input value={value} onChange={handleChange} {...props} />;
}

// Uncontrolled
<Input defaultValue="hello" />

// Controlled: onChange receives the event, so read the value from it
<Input value={value} onChange={(e) => setValue(e.target.value)} />
```

## `asChild`

Build the pattern in the form the project's primitives library documents, and take the import from
that library's install page. One such form, a slot component:

```jsx
// Slot: the slot component the project's primitives library exports (its install page names the import).
function Button({ asChild, ...props }) {
  if (asChild) return <Slot {...props} />;
  return <button type="button" {...props} />;
}
```

Each library's install and composition pages, with their pointer record, are in the primitives
table in `../../../component-libraries.md`.

## Forwarding refs

Always forward refs on components that wrap DOM elements. Where the project's React version takes
`ref` as a prop:

```tsx
function Button({ ref, children, ...props }: ButtonProps) {
  return (
    <button ref={ref} {...props}>
      {children}
    </button>
  );
}
```

Where it needs `forwardRef`:

```tsx
const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ children, ...props }, ref) => {
    return (
      <button ref={ref} {...props}>
        {children}
      </button>
    );
  }
);
```

Read which form the project's React version takes from the pointer below, and write new components
in that form.

- **Pointer**: <https://react.dev/reference/react/forwardRef#reference> (the notice that opens the
  page, above that section); correlate with
  <https://react.dev/learn/manipulating-the-dom-with-refs#accessing-another-components-dom-nodes>
- **As of**: 2026-10-29
- **Recheck trigger**: a React release changes how a component receives a ref.

## Spreading remaining props

Allow arbitrary HTML attributes to pass through:

```jsx
function Button({ variant, size, className, ...props }) {
  return (
    <button
      type="button"
      className={cn(buttonVariants({ variant, size }), className)}
      {...props}
    />
  );
}

// Now these work:
<Button data-testid="submit" aria-label="Submit form">
  Submit
</Button>
```

`cn` and `buttonVariants` stand for the project's own class-merging and variant helpers; use the
ones it already has.

## Sensible defaults

Defaults should cover 80% of usages:

```jsx
function Button({
  variant = "primary",
  size = "md",
  type = "button", // Not "submit" - safer default
  ...props
}) {
  // ...
}
```

## Slot pattern for optional sections

```jsx
function Card({ children, header, footer }) {
  return (
    <div className="card">
      {header && <div className="card-header">{header}</div>}
      <div className="card-content">{children}</div>
      {footer && <div className="card-footer">{footer}</div>}
    </div>
  );
}

// Usage
<Card
  header={<h2>Title</h2>}
  footer={<Button>Save</Button>}
>
  Main content
</Card>
```

## Error boundaries

The rule is in `../component-api.md`, section 11:

```jsx
function ComponentWithErrorBoundary({ children }) {
  return (
    <ErrorBoundary fallback={<ErrorFallback />}>
      {children}
    </ErrorBoundary>
  );
}
```

`ErrorBoundary` stands for the project's own error boundary, or the one from an error-boundary
package it already uses. With neither, write one as the pointer below shows, once, and reuse it.

- **Pointer**:
  <https://react.dev/reference/react/Component#catching-rendering-errors-with-an-error-boundary>
- **As of**: 2026-10-29
- **Recheck trigger**: the section moves, or a React release changes how a component catches
  render errors.

## File structure and exports

A default for a project with no layout of its own:

```text
components/
├── button/
│   ├── button.tsx        # Main component
│   ├── button.test.tsx   # Tests
│   └── index.ts          # Public exports
├── card/
│   ├── card.tsx
│   ├── card-header.tsx
│   ├── card-content.tsx
│   └── index.ts
```

```tsx
// components/card/index.ts
export { Card } from "./card";
export { CardHeader } from "./card-header";
export { CardContent } from "./card-content";

// Or as compound component
export { Card, CardHeader, CardContent } from "./card";
```
