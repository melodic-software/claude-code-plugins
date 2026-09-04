# Code-shape sketches

One example per code-shape row of Step 2. Every path, identifier, and file name in
these examples is a placeholder, not a reference to a real file. Keep only the
calls, files, props, states, and boundaries the current question needs.

## Pseudocode

For logic described in prose, or an algorithm before it is written. For
algorithmic work, pseudocode is more concise than the code will be.

```text
on(save)
  if content is unchanged
    return cached result
  write new content
  return fresh result
```

## Call tree

For a call path through named functions: orchestration, control-flow work, or any
backend-shaped problem.

```text
submitForm
  createSession
    persistPrompt
    launchAgent
  navigateToSession
```

## Component tree

For UI structure. Keep the state hooks and module boundaries that matter and leave
everything else out. File paths in parentheses.

```tsx
<SessionPage> (apps/example/src/routes/session.tsx)
  useSessionEvents()
  <SessionToolbar>
    <RunSkillButton> (packages/ui)
```

## Shallow file tree

For "where does this live" and for scoping a refactor: one line of responsibility
per entry, real box-drawing glyphs.

```text
src/
├── commands/       # parses user actions
├── sessions/       # owns session state
└── transport/      # sends API requests
```

## Types and signatures

For the shape of code before any of it exists: the types and the function
signatures, no bodies.

```ts
type Session = { id: string; prompt: string; startedAt: Date }

function createSession(prompt: string): Promise<Session>
function persistPrompt(session: Session): Promise<void>
function launchAgent(session: Session, signal: AbortSignal): Promise<void>
```

## Diff-shaped delta

When the point is what changes and the surrounding shape is already in the
conversation. Match the diff to the shape being changed.

A component change:

```diff
 <SessionPage>
   useSessionEvents()
   <SessionToolbar>
+    <RunSkillButton />
   <SessionTimeline>
+    <SkillResultCard />
```

A file-layout change:

```diff
 src/
 ├── commands/
+│   └── search.ts        # parses the query
 ├── sessions/
-└── transport.ts
+└── transport/
+    ├── client.ts
+    └── stream.ts
```

A call-tree or call-stack change:

```diff
 submitForm
   createSession
     persistPrompt
+    validateInput
     launchAgent
-  navigateToSession
+  navigateToSession
+    subscribeToEvents
```

A state or control-flow change:

```diff
 on(save)
-  write content
+  if content is unchanged
+    return cached result
+  write new content
+  invalidate cache
```

## The whole block

The fallback, when no sketch is smaller than the code itself: most of the block is
new, omitting context would hide ownership or order, or the user needs a copyable
target shape.

```ts
function slugify(title: string): string {
  return title.trim().toLowerCase().replace(/\s+/g, "-")
}
```

## Selecting a view

- Pick the smallest view that makes the key point clear.
- Place each visual next to the short text it supports.
- Keep only the calls, files, props, states, and boundaries needed to answer the
  user's current question or the options to resolve the current discussion point.
- You may use one of these, you may use several, it is unlikely you will use all
  of them. Use your judgement and do not overwhelm the user.
