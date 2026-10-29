# Component terms

The building blocks of an interface. Each entry gives the term, a definition, and the line between
it and the term most often confused with it.

## Components: `components`

### Button: `button`

The primary action trigger. Needs distinct default, hover, active, focus, disabled, and loading
states. Never more than one primary button in the same view.

**Versus:** a link navigates to another place; a button performs an action.

### Textarea: `textarea`

A multi-line input. Needs the same state treatment as a single-line input.

**Versus:** an input is one line; a textarea is several.

### Checkbox: `checkbox`

A toggle for a binary choice. Clicking the label should toggle it, not just clicking the box itself.

**Versus:** a switch implies an immediate effect; a checkbox is a choice usually applied on save. A
radio group allows only one.

### Switch: `switch`

A toggle for an on/off state. Implies an immediate effect. Use for settings that take effect without
a save action.

**Versus:** a checkbox is a choice applied on save; a switch takes effect at once.

### Modal / Dialog: `modal-dialog`

An overlay that interrupts the current flow to require attention. Focus must be trapped inside it
and the background should be inert to screen readers.

**Versus:** a sheet slides in from a screen edge and a drawer pulls up from the bottom; a modal
interrupts the flow in place.

### Drawer: `drawer`

A panel that pulls up from the base of the screen. A common mobile replacement for a dialog.

**Versus:** a sheet slides in from a side edge; a drawer pulls up from the bottom. A modal
interrupts in place.

### Tooltip: `tooltip`

A small label on hover that explains an element. Cannot contain interactive content. If you need a
link inside it, use a popover.

**Versus:** a popover is triggered by click and can hold interactive content; a tooltip cannot.

### Badge: `badge`

A small label attached to another element. Implies a count when numeric. When it carries a word like
New or a status label, it behaves more like a tag and needs different treatment.

**Versus:** a tag is standalone, selectable or removable; a badge is attached and informational.

### Accordion: `accordion`

Stacked sections that expand and collapse. Good for FAQs and secondary content. Not a substitute for
tabs when users need to compare across sections.

**Versus:** tabs show one section at a time in the same space for comparing; an accordion stacks
sections that expand. Accordion / collapse in `motion.md` is the animation it plays.

### Stepper: `stepper`

A multi-step flow that shows progress through a sequence. Showing all steps upfront sets
expectations. Hiding them creates anxiety.

**Versus:** progress shows completion of one process; a stepper shows position through a sequence of
steps.

### Navigation menu: `navigation-menu`

A top-level or flyout structure for moving between major sections. Labels should reflect how users
think about the product, not how it was built.

**Versus:** a sidebar is persistent navigation anchored to an edge; a navigation menu is the
top-level or flyout structure. Navigation in `information-architecture.md` is the whole system.

### Breadcrumb: `breadcrumb`

A trail showing location within a hierarchy. Lets users navigate back at depth without using the
browser's back button.

**Versus:** a stepper shows position in a sequence; a breadcrumb shows position in a hierarchy.

### Skeleton: `skeleton`

A placeholder that holds the shape of content while it loads. Keeps the layout stable and signals
what's coming. Better than a spinner for list and page loads.

**Versus:** a spinner shows waiting without the content's shape; a skeleton holds that shape.
Skeleton / shimmer in `motion.md` is the sheen animation on it.

### Avatar: `avatar`

A small image representing a user or entity. Needs a fallback when the image fails, usually initials
or a generic icon.

**Versus:** an icon represents an action or object type; an avatar represents one user or entity.

### Data table: `data-table`

A structured grid of rows and columns. Numbers should be right-aligned with tabular nums. Proper
alignment does the work zebra striping is often used to compensate for.

**Versus:** a list shows one item per row without columns to compare; a data table aligns values in
columns.

### Command menu: `command-menu`

A keyboard-triggered search interface for navigating or executing actions. Common in tools where
power users want to avoid the mouse.

**Versus:** a select picks one value for a field; a command menu searches actions and places.

### Separator: `separator`

A visual divider between items or sections. Often overused when better spacing would do the same
job.

**Versus:** negative space separates by spacing alone; a separator draws a line.

### Input: `input`

A text entry field. Needs a persistent label above it, not just a placeholder. Each state (default,
hover, focus, error, disabled) should be visually distinct.

**Versus:** a textarea is multi-line; an input is a single line. A combobox adds a filtered
dropdown.

### Select: `select`

A dropdown for choosing one option from a list. The native HTML element is accessible but hard to
style. Custom selects need careful keyboard and focus handling.

**Versus:** a combobox lets the user type to filter; a select only lets them pick.

### Radio group: `radio-group`

A set of options where exactly one can be selected. Distinct from checkboxes, which allow multiple.

**Versus:** a checkbox allows several choices; a radio group exactly one.

### Slider: `slider`

A control for selecting a value within a range. Should update the value live on drag, not only on
release.

**Versus:** a stepper input changes a value by fixed increments; a slider picks a value within a
range by dragging.

### Sheet: `sheet`

A panel that slides in from the screen edge. Common on mobile for secondary navigation or contextual
actions. Same focus and dismissal rules as a modal.

**Versus:** a drawer pulls up from the bottom; a sheet slides in from a side edge. A modal
interrupts in place.

### Popover: `popover`

A small overlay anchored to an element, triggered by click. Can contain interactive content like
links or buttons. Different from a tooltip, which cannot.

**Versus:** a tooltip is a label on hover with no interactive content; a popover is triggered by
click and can hold it.

### Toast: `toast`

A temporary notification that auto-dismisses. Duration should reflect reading time, not a flat 2
seconds regardless of length.

**Versus:** an inline alert stays in the page until dismissed; a toast is temporary and dismisses
itself.

### Tag: `tag`

A label that categorizes content. Tags are standalone, selectable, or removable. Badges are attached
and informational. They are not the same thing.

**Versus:** a badge is attached and informational; a tag is standalone, selectable or removable.

### Tabs: `tabs`

Switches between related views in the same space. Best for filtering the same content by time or
category. Not for navigating unrelated sections.

**Versus:** an accordion stacks sections that expand; tabs switch views in one space. Navigation
moves between unrelated sections.

### Carousel: `carousel`

A horizontally scrollable row of items. On desktop, often a sign the layout hasn't been solved. On
mobile, a natural pattern. Either way, the first item gets most of the attention.

**Versus:** pagination moves between pages of a list; a carousel scrolls a row of items
horizontally.

### Sidebar: `sidebar`

Persistent navigation anchored to an edge. Common in dashboards. Works well when users move between
sections frequently.

**Versus:** a navigation menu is a top-level or flyout structure; a sidebar stays visible at an
edge.

### Pagination: `pagination`

Controls for moving between pages of content. Use when the full list is too long to load at once.
Infinite scroll is an alternative with different tradeoffs.

**Versus:** infinite scroll loads more as the user reaches the end; pagination uses explicit page
controls.

### Spinner: `spinner`

An indeterminate loading indicator. Good for short action-level waits. For page or list loads, a
skeleton is almost always better.

**Versus:** a skeleton holds the shape of the content; a spinner only shows that something is
happening. Progress shows how much is done.

### Card: `card`

A contained surface grouping related content. The inner radius should be smaller than the outer,
calculated from the parent's border width and padding, floored at zero. Making the full surface a link makes text selection impossible.

**Versus:** a separator divides with a line; a card groups with a contained surface.

### Combobox: `combobox`

An input that filters a dropdown as you type. Combines the feel of a text field with the constraints
of a select.

**Versus:** a select only picks from the list; a combobox filters it as the user types.

### Progress: `progress`

A bar showing completion through a determinate process. For unknown durations, use a spinner
instead.

**Versus:** a spinner is indeterminate; progress is determinate and shows how much is done.

### Empty state: `empty-state`

What a view shows when there is no content yet. Should explain why and offer a first action. No
items found tells the user nothing.

**Versus:** Empty state in `information-architecture.md` is the same view seen from the structure; a
skeleton is content still loading, not absent.
