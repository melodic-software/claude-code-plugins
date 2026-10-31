# Forms and inputs

Read this when a web screen has anything a person types into or presses: a form, a text input, a
textarea, a search field, a login or signup flow, a settings page, a checkout, a button, a checkbox
or a submit handler. The project's own form components, validation library and conventions win over
every rule here; suggest a change to them, never override them.

Forms are where users do real work, and they notice every rough edge: the label that doesn't focus
the input, the page that zooms on iOS, the button that fires twice, the Enter key that does nothing.
None of these are hard to fix; they're just easy to forget. Wire up the semantics the platform gives
you (`<form>`, `<label>`, `<button>`), then layer on the details below.

The examples are HTML, CSS and React (JSX). In another framework, keep the behavior and write it in
that framework's own idiom. The CSS that implements these rules is in `/user-interface:write-css`:
its `interaction.md` recipes, named by id beside the rule that uses them.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like. Forms are also where launch-day money is lost: signup,
checkout, invite, settings. Every check here is a rough edge someone hits in their first session.
Sweep the forms in order of what they cost when broken: auth and checkout first, then creation
flows, then settings.

Three form rules belong to other concerns, one home each: the 16px floor on input text is the
`touch` concern; a visible `:focus-visible` state on every input and control is the `accessibility`
concern, and so is an error that is not signaled by color alone. A field's focus ring takes its
color from the `--focus-ring` token, whose rule is the `color` concern's.

Contents: 1 a worked example, 2 labels, 3 input type and `autocomplete`, 4 input decorations, 5
autofocus, 6 the `<form>` and Enter, 7 buttons and their loading state, 8 failed submits, 9
validation timing and error messages, 10 input states, 11 checkbox and control dead zones, 12
destructive actions, 13 prefill, 14 unsaved work, 15 accessible primitives.

## 1. A worked example

A domains settings page has an add-domain field that accepts anything, and Enter doesn't submit.
The forms pass was asked to fix the validation and the submit states. After it, a visually hidden
`<label>` "Domain" sits on an input with `inputmode="url"`, `autocomplete="off"` and
`spellcheck="false"`, inside a `<form>` with a `type="submit"` button "Add domain". Typing `asdf`
and pressing Enter shows "Enter a domain like example.com." under the field with an icon, sets
`aria-invalid="true"` and `aria-describedby` on the input, and adds nothing. A real domain clears the
error; the button turns disabled and reads "Adding…" until the row appears.

The input has a label now. It's visually hidden, because the button next to it already says what the
field is for, but a screen reader still announces it. It also sits inside a `<form>`, so Enter
submits.

`asdf` gets an error next to the field, with an icon, so the message doesn't rely on red alone. The
line for that error is always reserved, which means the page doesn't jump when it shows up. While
the request runs, the button is disabled and says what's happening, so it can't fire twice.

Keeping the button's width and the reserved error line steady while they change is the
`layout-stability` concern.

## 2. Every input gets an associated label

Clicking the label must focus the input:

```html
<label for="email">Email</label>
<input id="email" type="email" />

<!-- Or wrap the input -->
<label>
  Email
  <input type="email" />
</label>
```

**Audit: Blocking.** An input with no associated label, or a label that doesn't focus its input when
clicked.

## 3. Use the right input type and `autocomplete`

```html
<input type="email" />    <input type="password" />
<input type="tel" />      <input type="url" />
<input type="number" />   <input type="search" />
```

The right `type` gets you the right mobile keyboard, browser validation, and autofill behavior for
free. The right `autocomplete` lets the browser and password manager fill the form in one tap, which
on a phone is the difference between a signup and a bounce.

```html
<input type="email"    autocomplete="email" />
<input type="text"     autocomplete="username" />          <!-- login, beside current-password -->
<input type="password" autocomplete="current-password" />  <!-- login -->
<input type="password" autocomplete="new-password" />      <!-- signup, change password -->
<input type="text"     autocomplete="one-time-code" inputmode="numeric" />
<input type="tel"      autocomplete="tel" />
```

Kill noisy browser behaviors when they don't help. Disable `spellcheck` and `autocomplete` most of
the time for cleaner UX (search fields, slugs, API keys: anything that isn't a real address or
identity field). Keep autocomplete ON for email, name, username, address, and payment fields: there
it genuinely helps. Usernames and one-time codes keep `spellcheck="false"` but take their own
tokens, `username` and `one-time-code`, so the browser or password manager can fill them. Disable
1Password's overlay on fields where it doesn't belong (a search box, a project name):

```html
<input type="text" spellcheck="false" autocomplete="off" />
<input data-1p-ignore />
```

- **Pointer**: MDN, the `autocomplete` attribute, "Avoid disabling autocomplete",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/autocomplete#avoid_disabling_autocomplete>
- **As of**: 2026-10-29
- **Recheck trigger**: the page renames or drops the `username` or `one-time-code` token.

- **Pointer**: 1Password, compatible website design, "Ignore offers to save or fill specific
  fields",
  <https://www.1password.dev/web/compatible-website-design/#ignore-offers-to-save-or-fill-specific-fields>
- **As of**: 2026-10-29
- **Recheck trigger**: that section renames or drops the `data-1p-ignore` attribute.

Hunt for: `type="text"` on email, phone, URL, and search fields; password fields with no
`autocomplete`; `autocomplete="off"` on identity, address, or payment fields.

**Audit: Important.** An input with the wrong `type`, a password field with no `autocomplete`, or
`autocomplete="off"` on an identity, address or payment field.

## 4. Input decorations overlay the input, they don't sit beside it

Prefix/suffix icons and labels should be absolutely positioned on top of the input (with padding
making room), not rendered as sibling elements. Otherwise clicking them does nothing and the "input"
border lies about the hit area:

```css
.input-wrapper {
  position: relative;
}

.input-icon {
  position: absolute;
  inset-inline-start: 12px;
  top: 50%;
  transform: translateY(-50%);
  pointer-events: none;
}

.input-field { padding-inline-start: 40px; }
```

Non-interactive decorations get `pointer-events: none`. Clickable decorations (like a clear button)
should refocus the input:

```jsx
<button
  type="button"
  aria-label="Clear search"
  className="input-icon-button"
  onClick={() => {
    setQuery("");
    inputRef.current?.focus();
  }}
>
  <XIcon aria-hidden="true" />
</button>
```

`type="button"` keeps the clear button from submitting the form, and `aria-label` names an
icon-only button.

Hunt for: wrappers with `border` + `focus-within` styling containing an icon and a borderless input
side by side.

**Audit: Important.** An icon rendered as a sibling of the input, so clicking it does nothing, or a
clear button that leaves focus off the input.

## 5. Autofocus: yes in modals, never on touch

Autofocus the first input when a modal opens (if the modal contains one). Do NOT autofocus on touch
devices: it pops the keyboard open unexpectedly. Gate it on a coarse pointer:

```jsx
const inputRef = useRef(null);

useEffect(() => {
  if (!window.matchMedia("(pointer: coarse)").matches) inputRef.current?.focus();
}, []);

<input ref={inputRef} />
```

The check runs in an effect, after mount, so server and client render the same markup and
hydration has nothing to mismatch.

`(pointer: coarse)` describes the primary pointing device only. A hybrid device (a touch laptop, a
tablet with a mouse) can report a fine primary pointer; to ask about any pointer, use `any-pointer`
and `any-hover`. The same media features gate hover styles in the
`hover-styles-only-where-hover-exists` recipe. To ask in script whether the device has touch
hardware at all, check `navigator.maxTouchPoints > 0`.

- **Pointer**: MDN, the `pointer` media feature,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/@media/pointer#syntax>, and
  `Navigator.maxTouchPoints`,
  <https://developer.mozilla.org/en-US/docs/Web/API/Navigator/maxTouchPoints#value>
- **As of**: 2026-10-29
- **Recheck trigger**: either page changes what `pointer` or `maxTouchPoints` describes, or the
  first stops pointing at `any-pointer`.

Hunt for: `autoFocus` / `autofocus` / `.focus()` in a mount effect with no pointer gate.

**Audit: Important.** Autofocus with no pointer gate, shoving the keyboard into the face of a phone
user.

## 6. Always wrap inputs in a `<form>`: Enter must submit

Without a wrapping `<form>`, Enter does nothing, password managers can't find the fields, and the
mobile keyboard's return key is dead. The user types their password, hits Enter, and the page sits
there.

```jsx
function handleSubmit(e) {
  e.preventDefault();
  // send the fields
}

<form method="post" onSubmit={handleSubmit}>
  <input type="email" name="email" />
  <button type="button" onClick={onCancel}>Cancel</button>
  <button type="submit">Continue</button>
</form>
```

`method="post"` matters on a login or signup form: a submit before the script loads goes out as a
POST, not a GET that puts the email and password in the URL. A form that posts to your own server
keeps the framework's CSRF protection on; don't hand-roll a token or switch it off for the form. A
hand-written `fetch` to an API route has no CSRF protection unless the framework or the route adds
it: use the framework's token or middleware on that route, and treat SameSite session cookies as a
second layer, not the protection (the second pointer says why).

- **Pointer**: OWASP Cross-Site Request Forgery Prevention Cheat Sheet, "Built-In Or Existing CSRF
  Implementations",
  <https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html#built-in-or-existing-csrf-implementations>,
  and "Limitations of SameSite",
  <https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html#limitations-of-samesite>
- **As of**: 2026-10-29
- **Recheck trigger**: the cheat sheet changes its guidance on built-in protections or on SameSite
  as a defense.

For textareas (where Enter inserts a newline), support `Cmd+Enter` (Mac) / `Ctrl+Enter` (Windows) to
submit:

```jsx
<textarea onKeyDown={(e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "Enter" && !e.nativeEvent.isComposing) {
    e.preventDefault();
    e.currentTarget.form?.requestSubmit();
  }
}} />
```

Submit with `requestSubmit()`, never `submit()`; the pointer says what it runs. The
`isComposing` check leaves Enter alone while an input method is still composing text.

- **Pointer**: MDN, `HTMLFormElement.requestSubmit()`, usage notes,
  <https://developer.mozilla.org/en-US/docs/Web/API/HTMLFormElement/requestSubmit#usage_notes>, and
  `KeyboardEvent.isComposing`,
  <https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/isComposing#browser_compatibility>
- **As of**: 2026-10-29
- **Recheck trigger**: the `isComposing` page's compatibility data changes, or the first page
  changes what `requestSubmit()` runs.

A textarea that grows with its text: recipe `textarea-that-grows-with-its-content`.

Hunt for: inputs with a submit `onClick` on a sibling button and no `<form onSubmit>` ancestor;
`<form>` with no `onSubmit`; buttons inside a form with no `type` (a bare `<button>` is a submit
button, so "Cancel" submits). A `<form>` with an `action` does not need `onSubmit`.

**Audit: Blocking.** On an auth or checkout form: a lone input with no `<form>`, so Enter silently
does nothing; a `<form>` with no `onSubmit` and no `action`; or a button inside the form with no
`type`.

**Audit: Important.** The same on any other form, or a textarea with no Cmd/Ctrl+Enter submit.

## 7. Buttons are `<button>` elements, with a loading state

Never put click handlers on elements that aren't buttons:

```jsx
{/* Good */}
<button onClick={handleClick}>Click me</button>
{/* Bad */}
<div onClick={handleClick}>Click me</div>
<span onClick={handleClick}>Click me</span>
```

**Audit: Blocking.** A `<div onClick>` or `<span onClick>` "button", invisible to keyboards and
screen readers. This is the one home of the check; the `accessibility` concern names it rather than
tagging it again.

A submit button that stays enabled sends the request twice on a double-click or an impatient second
tap: two charges, two invites, two projects. Disable the button while submitting to prevent
duplicate network requests, and say what's happening:

```jsx
<button type="submit" disabled={isSubmitting}>
  {isSubmitting ? "Saving…" : "Save changes"}
</button>
```

A disabled button stops a second click, not a network retry or a second tab, so the server treats a
repeated create, pay or invite request as one, for example by an idempotency key the client sends.

The `finally` branch re-enables the button; a form that stays disabled forever after a failed
request is the same bug from the other side. In React with form actions, take the pending state
from `useFormStatus` in the submit button's own component; the pointer says where the hook must be
called.

- **Pointer**: React, `useFormStatus`, Caveats,
  <https://react.dev/reference/react-dom/hooks/useFormStatus#caveats>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes what `pending` reports or where the hook must be called.

Hunt for: submit handlers with no `isSubmitting` / `isPending` / `useFormStatus` state;
`<button type="submit">` with no `disabled` prop; async `onClick` handlers on "Create", "Pay",
"Send", "Invite", "Delete".

**Audit: Blocking.** A submit button that stays enabled while its request is in flight and fires the
request twice.

A button with no pressed state feels unresponsive, and on touch (where hover doesn't exist) it gives
no feedback at all until the action completes. Make buttons feel pressable with a subtle scale on
`:active`; how far it scales, and how far is too far, is the `motion` concern's (`press`). Recipe:
`press-feedback`.

Hunt for: the shared `Button` component with `:hover` but no `:active`.

**Audit: Important.** A button with no `:active` state.

If a button's action has a keyboard shortcut, surface it as a tooltip:

```jsx
<Tooltip content="Save (Cmd+S)">
  <button onClick={save}>Save</button>
</Tooltip>
```

**Audit: Suggestion.** A button whose action has a keyboard shortcut that nothing on screen shows.

## 8. A failed submit says so, and keeps what was typed

The happy path was tested. The unhappy path is a swallowed `catch`, a spinner that never stops, or a
form that clears itself on error and makes the user retype everything.

On failure, keep every field's value, re-enable the button, and show a message next to the form that
says what happened and what to do ("We couldn't save your changes. Check your connection and try
again."). Field-level server errors ("That email is already registered") render next to their field
(section 9).

Login and password reset are the exception: their message reads the same whether or not the
account exists ("Email or password is incorrect"; "If that email has an account, we sent a reset
link"), so the form doesn't reveal who has an account. Signup is the same, where the product
allows it: the form shows one neutral message for a new and an existing address ("Check your email
to finish signing up"), and the email carries the details, so "That email is already registered"
goes in the email, not on the form.

- **Pointer**: OWASP Authentication Cheat Sheet, "Authentication Responses",
  <https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html#authentication-responses>
- **As of**: 2026-10-29
- **Recheck trigger**: the section changes which flows must answer with a generic message.

Hunt for: `catch` blocks that only `console.error`; `try` with no `catch` around a `fetch`; no
`finally` resetting the submitting state; form `reset()` called before the response is checked; no
handling for a non-2xx response (`fetch` doesn't throw on a 500).

**Audit: Blocking.** A failed submit that is swallowed, spins forever, or clears what the user
typed.

## 9. Validate late, not on every keystroke

Don't flag a field as invalid while the user is still typing their first attempt: validate on blur
or on submit. Once a field HAS shown an error, switch to validating on change so the error clears the
moment they fix it ("reward early, punish late"). In CSS alone, recipe
`form-feedback-with-user-invalid` waits for the user the same way.

With react-hook-form, use `mode: "onBlur"` or `"onTouched"` with `reValidateMode: "onChange"`.

- **Pointer**: react-hook-form, `useForm`, the `mode` and `reValidateMode` options,
  <https://react-hook-form.com/docs/useform#mode> and
  <https://react-hook-form.com/docs/useform#reValidateMode>
- **As of**: 2026-10-29
- **Recheck trigger**: the page renames those options or changes what `onTouched` or
  `reValidateMode` does.

Hunt for: validation run inside `onChange` with no touched or submitted gate; schema resolvers
configured with `mode: "onChange"`.

**Audit: Important.** Validating on every keystroke, yelling "invalid email" after one character.

Colocate error messages with the field that caused them, not in a summary at the top. Each message
renders directly under the field that caused it, wired with `aria-describedby`, and tells the user
how to fix it:

```jsx
<div className="field">
  <label htmlFor="email">Email</label>
  <input id="email" type="email" aria-invalid={!!error} aria-describedby="email-error" />
  <span id="email-error" className="error">{error}</span>
</div>
```

The error `<span>` always renders, empty until there is an error, so its line stays reserved and
`aria-describedby` always names an element that exists.

| Instead of | Write |
| --- | --- |
| "Invalid input" | "Your email must include an @" |
| "Required" | "Enter your company name" |
| "Password error" | "Use at least 8 characters" |

After a failed submit, move focus to the first invalid field so the keyboard and screen reader user
lands on the problem.

Hunt for: a single `{error && <Alert>}` at the top of a multi-field form; messages like "Invalid
input", "Error", "Required", "Validation failed".

**Audit: Important.** An error summary at the top of the form instead of next to the broken field,
an error not wired to its field, or a message that names no fix.

## 10. Inputs show every state

Inputs need visually distinct default, hover, focus, and error states. If they all look identical,
users can't tell active from broken.

**Audit: Important.** An input whose hover, focus or error state looks the same as its default.

## 11. No dead zones on checkboxes and controls

The label, the control, AND the gap between them must all be clickable. A 16px checkbox with a label
that doesn't toggle it is a tap target nobody can hit.

```css
.checkbox-wrapper {
  display: flex;
  align-items: center;
  cursor: pointer;
}

/* Make the entire row clickable, not just the checkbox */
.checkbox-wrapper label { cursor: pointer; flex: 1; padding-inline-start: 8px; }
```

The space between the control and its text is the label's padding, not a flex `gap`: a gap belongs
to neither element, so a click there toggles nothing.

Or wrap everything in one label:

```html
<label class="checkbox-row">
  <input type="checkbox" />
  <span>Remember me</span>
</label>
```

Don't reach for recipe `hit-area-larger-than-the-visual` on a checkbox: the wrapping label is how
a checkbox's target grows.

Hunt for: checkbox/radio `<input>` with a sibling `<span>` or `<p>` instead of a `<label>`; flex
`gap` between an input and its `<label for>`.

**Audit: Important.** A checkbox or radio row whose label or gap does not toggle the control.

## 12. Destructive actions require confirmation

Delete, remove, revoke, cancel subscription, leave team: a confirmation step before anything
irreversible, or an undo window after it. A proper confirmation dialog, not `window.confirm()`. The
confirm button names the outcome ("Delete project"), not "OK" or "Yes".

Adding a confirmation changes behavior, so when none exists apply it only if the project already has
a dialog primitive and a pattern to follow. Otherwise it goes on the human list.

Hunt for: handlers named `delete*` / `remove*` / `revoke*` / `cancel*` wired straight to a button;
`window.confirm(`; a destructive button styled the same as the primary and sitting next to it.

**Audit: Blocking.** An irreversible destructive action with no confirmation and no undo.

**Audit: Important.** Any other destructive action with no confirmation, a `window.confirm()`, or a
confirm button labeled "OK" or "Yes".

## 13. Prefill everything you can

Every field the app already knows the answer to is friction. Use the logged-in user's data to
prefill forms whenever possible: their name and email on a support form, the current value on an
edit form, the invite's email on the signup it leads to. When linking to a form, prefill it from the
request context: e.g. a "Change username" link should land on a form prefilled with: "I'd like to
change my username to:"

Hunt for: edit forms whose `defaultValue`s are empty; signup pages that ignore an `?email=` param the
invite link carries. Prefill that email from the invite the server looks up by the link's token, not
from the `?email=` param itself, which anyone can edit.

**Audit: Suggestion.** A form that asks for something the app already knows.

## 14. Unsaved work survives an accident

A long form (an editor, a multi-step flow, a settings page) that loses everything on an accidental
back-swipe or refresh. Warn on `beforeunload` while the form is dirty, or persist the draft to
`sessionStorage`. Leave passwords, card numbers and one-time codes out of a persisted draft.

Hunt for: multi-step flows holding all state in one component's `useState`; rich-text editors with
no autosave or dirty guard.

**Audit: Suggestion.** A long or multi-step form that loses its input on a refresh or back-swipe.

## 15. Build on accessible primitives

Which accessible primitives library to build form controls on, and the accessibility bar it must
meet, is in `../../component-libraries.md`.
